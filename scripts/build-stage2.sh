#!/usr/bin/env bash
# Stage 2: rebuild the repository inside the repository.
#
# WHAT STAGE 2 IS FOR
#
# Every package stage 1 produced was compiled against UBUNTU's libraries. That
# is not a defect -- Arch's glibc needs an Arch gcc which needs an Arch glibc,
# so the first pass has nowhere else to start -- but it leaves host artefacts
# baked in. scripts/test-chroot.sh names nine of them precisely: binaries that
# ask for libgpgme.so.11, libnettle.so.8, libicuuc.so.76 and six more, at the
# host's soname versions, while the repository ships Arch's. Stage 2 dissolves
# all nine by rebuilding each package against what the repository actually has.
#
# THE CONSTRAINT THAT SHAPES THIS SCRIPT
#
# pacman cannot run inside the stage-1 rootfs. libalpm was linked against the
# host's gpgme, so the binary is there and does not start:
#
#   pacman: error while loading shared libraries: libgpgme.so.11
#
# So the rootfs is populated from OUTSIDE, with the host's pacman and --root,
# the way scripts/test-chroot.sh does. The chroot is used only to BUILD. That
# is not a workaround, it is the order the problem has: stage 2's own output
# is the first pacman that will run on the target.
#
# makepkg, by contrast, is a shell script, and it works.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Stage 2 rebuilds the same packages in the same order; packages.sh explains
# why that order is not re-derived here.
source "$HERE/packages.sh"
# watched(): bootstrap-pacman.sh cannot be sourced here -- see lib-watch.sh.
source "$HERE/lib-watch.sh"
WORK="${WORK:-$HOME/work/arch-s390x}"
REPO1="${REPO1:-$WORK/repo/s390x}"
REPO2="${REPO2:-$WORK/repo2/s390x}"
ROOT="${ROOT:-$WORK/rootfs-stage2}"
CONF="$WORK/pacman-stage2.conf"
CACHE="$WORK/pacman-stage2.cache"
CONF2="$WORK/pacman-stage2-both.conf"
STATE2="$WORK/stage2.state"
PATCH_DIR="${PATCH_DIR:-$HERE/../patches/pkgbuild}"
BUILDER="${BUILDER:-$(id -un)}"
BUILD_UID="$(id -u)"
BUILD_GID="$(id -g)"

# The chroot's contents. Two groups, and the second is the one the dependency
# resolver could never have told us about: nothing in the repository DEPENDS on
# bison or fakeroot, they are simply what a build needs to happen.
CHROOT_PKGS=(
    # A system that reaches a shell and can read a package.
    filesystem glibc bash coreutils sed grep gawk findutils file which
    tar gzip xz bzip2 zstd libarchive diffutils patch
    # The toolchain.
    gcc binutils make m4 autoconf automake libtool pkgconf
    bison flex texinfo groff gettext
    # makepkg itself, and the one thing it cannot do without.
    pacman fakeroot
    # rsync, which is not a runtime dependency of anything here. The kernel's
    # headers_install target runs it, so linux-api-headers -- the first package
    # stage 2 tries -- stopped on `rsync: command not found`. The host had it
    # from apt, which is exactly why stage 1 never mentioned it.
    rsync
    # The same class, named by the failures of the first full pass rather than
    # guessed at. Each one is here because a package said so:
    #
    #   gperf     coreutils, diffutils, systemd, libseccomp
    #   wget      sed, grep, findutils
    #   patchelf  curl
    #   inetutils gnupg, for hostname
    #   libxslt   shadow, for xsltproc
    #   swig      audit
    #   help2man  flex
    #
    # libxslt is NOT here, and cannot be: it will not build on the host at all.
    #
    #   configure: error: Version 2.14.5 found. You need at least libxml2
    #   2.15.1 for this version of libxslt
    #
    # 2.14.5 is Ubuntu's libxml2. Ours is 2.15.3 -- and it exists only inside
    # this chroot, which is the one place libxslt can be built. So it is built
    # BY stage 2 rather than installed into it, which is why it sits in
    # STAGE2_FIRST instead. Listing it here would fail make_rootfs with "target
    # not found" against a repository that will never contain it.
    gperf wget patchelf inetutils swig help2man
    # scdoc: kmod's meson asks for it by name.
    scdoc
    #
    # The Python packaging set is NOT here. Those six cannot be built on the
    # host at all -- see STAGE2_FIRST below -- so they come from repo2 and are
    # listed in CHROOT_STAGE2_PKGS. python-flit-core is the exception: it is
    # pure data with no install-path logic, so the host builds it correctly.
    python-flit-core
    # libxcrypt-compat, for a reason no declaration expresses. perl declares
    # `libxcrypt` and `libcrypt.so`, both satisfied by libxcrypt, which ships
    # libcrypt.so.2. But perl's BINARY was linked on the host against Ubuntu's
    # libcrypt.so.1, so it does not start:
    #
    #   /usr/bin/perl: error while loading shared libraries: libcrypt.so.1
    #
    # The repository does ship that soname -- in libxcrypt-compat, a separate
    # sub-package -- so this is neither a missing package nor a soname the
    # audit should have flagged. It is a third thing: the dependency
    # declarations cannot pull it in, because they name the unversioned soname
    # that the newer library also provides. Listed explicitly, because nothing
    # will deduce it.
    libxcrypt-compat
    # git: 51 PKGBUILDs use git sources, and makepkg validates the clone even
    # under --noextract.
    git
    # meson and cmake, with the python they are written in. Ten PKGBUILDs
    # call arch-meson and four call cmake, so without these stage 2 could
    # rebuild most of the repository and then stop.
    python meson ninja cmake
)

log()  { printf '\n== %s ==\n' "$*"; }
die()  { printf 'stage2: %s\n' "$*" >&2; exit 1; }

# A PREDICATE and a fatal check, kept apart on purpose.
#
# require_space calls die, which exits. Using it inside the rebuild loop as
# `require_space || break` looks like a clean early stop and is not one: the
# break is unreachable, the run ends mid-loop, and the summary naming which
# packages were rebuilt and which failed is never printed. At the start of the
# run, exiting IS the right answer -- there is nothing to summarise yet.
space_ok() {
    local free_mb
    free_mb=$(df -Pm "$WORK" | awk 'NR==2 {print $4}')
    if [ "${free_mb:-0}" -lt 8192 ]; then
        printf '  only %s MiB free under %s; need 8192\n' "${free_mb:-0}" "$WORK" >&2
        return 1
    fi
}

require_space() { space_ok || die "not enough disk space to start"; }

make_rootfs() {
    log "Populating the stage-2 rootfs from stage 1"
    cat > "$CONF" <<EOF
[options]
Architecture = s390x
SigLevel = Never
[core]
Server = file://$REPO1
EOF
    sudo rm -rf "$ROOT" "$CACHE"
    sudo mkdir -p "$ROOT/var/lib/pacman" "$CACHE"
    # EVERYTHING in stage 1, not a hand-picked core.
    #
    # CHROOT_PKGS grew one name at a time, each added because a build said so.
    # It reached 158 of the 190 packages stage 1 had produced, and the 32 that
    # were missing failed builds in a way that never mentioned them:
    #
    #   openldap: configure: error: --enable_argon2=yes requires --with-argon2
    #
    # while the PKGBUILD already passes --with-argon2=libsodium and libsodium
    # sits in repo/s390x, simply not installed. configure had looked for a
    # library, not found it, and reported a missing OPTION. krb5's "libldap not
    # found", libsasl's "Could not locate OpenLDAP", lvm2's "libudev >= 143" and
    # audit's undefined SASL symbol are all the same sentence in different words.
    #
    # Stage 2 builds with --nodeps, so nothing installs a build dependency for
    # it. The alternative -- dropping --nodeps -- needs a working in-chroot
    # pacman, and that pacman is one of the packages being rebuilt.
    #
    # So: install the distribution we have. This IS what stage 2 means -- the
    # distribution rebuilt inside itself -- and every package in there is ours.
    # CHROOT_PKGS stays as the documented core, and it is what the fallback
    # below installs if the full set will not resolve.
    local all=() f pn
    shopt -s nullglob
    for f in "$REPO1"/*.pkg.tar.*; do
        pn=$(bsdtar -xOf "$f" .PKGINFO 2>/dev/null | sed -n 's/^pkgname = //p')
        [ -n "$pn" ] || continue
        # Alternatives, which a repository holds happily and a system cannot.
        printf ' %s ' "${CHROOT_EXCLUDE[*]}" | grep -q " $pn " && continue
        all+=("$pn")
    done
    shopt -u nullglob
    printf '  %s packages in stage 1, %s excluded as alternatives\n' \
        "${#all[@]}" "${#CHROOT_EXCLUDE[@]}"
    # Two log files, not one. The first version wrote both attempts to
    # stage2-install.txt, so the fallback's success overwrote the failure that
    # caused it and the reason was gone.
    if ! sudo pacman --root "$ROOT" --config "$CONF" --cachedir "$CACHE" \
            --noconfirm -Sy "${all[@]}" > "$WORK/stage2-install-full.txt" 2>&1; then
        # pacman puts the reason on a `::` line, and the first version of this
        # grep matched three phrases that did not include it -- so it printed
        # NOTHING between "did not resolve" and "falling back". A fallback that
        # cannot say why it happened is the thing this message exists to
        # prevent; it took reproducing the command by hand to learn that the
        # answer was one package wanting zsh.
        printf '  the full set did not resolve:\n'
        # THREE kinds of refusal, because two greps in a row printed nothing
        # here and each time the fallback looked unexplained: a dependency it
        # cannot satisfy (`:: unable to satisfy`), a package pair in conflict,
        # and a FILE owned by two packages (`exists in both`). The last one is
        # invisible to -Syp, which is why the exclusion list was wrong twice.
        grep -E "^error|^:: unable|in conflict|exists in both|target not found" \
            "$WORK/stage2-install-full.txt" | sed 's/^/    /' | cut -c1-100 | head -6
        printf '  falling back to CHROOT_PKGS (see stage2-install-full.txt)\n'
        sudo pacman --root "$ROOT" --config "$CONF" --cachedir "$CACHE" \
            --noconfirm -Sy "${CHROOT_PKGS[@]}" > "$WORK/stage2-install.txt" 2>&1 \
            || { tail -20 "$WORK/stage2-install.txt" >&2; die "populate failed"; }
    fi
    printf '  %s packages installed\n' "$(sudo ls "$ROOT/var/lib/pacman/local" | wc -l)"

    # Put stage 2's own output back on top of it.
    #
    # make_rootfs wipes and repopulates from stage 1 on EVERY run, which is
    # what makes the chroot reproducible -- and what would make stage 2
    # unresumable, because stage2.state survives while the packages it names do
    # not. The second invocation would say "already rebuilt, skipping" about
    # packages that had just been thrown away, and the next build would link
    # against stage-1 libraries while the record claimed otherwise. Silent, and
    # the kind of thing found weeks later in an artefact.
    #
    # Stage 2 is a hundred and thirty-three packages. It will not finish in one
    # invocation, so resuming has to be correct rather than approximately
    # correct.
    #
    # --nodeps for the same reason the per-package install uses it: a chroot
    # halfway through stage 2 is a mixed population, some packages declaring
    # versioned soname dependencies and some declaring names. -U is fed the
    # files directly, so --nodeps installs exactly these and not a resolved
    # closure -- correct here, since stage 1 already supplied the closure just
    # above.
    # ONLY WHAT WAS ALREADY THERE. Restoring everything in repo2 fails:
    #
    #   :: zlib-ng-compat-2.3.3-1 and zlib-1:1.3.2-3 are in conflict
    #   stage2: restoring stage-2 output failed
    #
    # Both are legitimate stage-2 output -- zlib-ng's PKGBUILD produces
    # zlib-ng-compat, and zlib is its own package. A REPOSITORY holds both
    # happily; an installed system cannot, because zlib-ng-compat replaces
    # zlib. Stage 1 chose zlib for this chroot, and that choice is not stage
    # 2's to revisit while it is rebuilding.
    #
    # So the filter is not a conflict list, which would need extending every
    # time a package like this appeared. It is the intent stated exactly: put
    # back the stage-2 build OF WHAT IS INSTALLED. A stage-2 package for
    # something the chroot does not have was never part of this chroot, and
    # installing it would quietly grow the build environment past what
    # CHROOT_PKGS defines.
    shopt -s nullglob
    local cand=("$REPO2"/*.pkg.tar.*)
    shopt -u nullglob
    local back=() inst f pn
    if [ "${#cand[@]}" -gt 0 ]; then
        inst=$(sudo pacman --root "$ROOT" --config "$CONF" -Qq 2>/dev/null)
        local pb
        for f in "${cand[@]}"; do
            pn=$(bsdtar -xOf "$f" .PKGINFO 2>/dev/null | sed -n 's/^pkgname = //p')
            [ -n "$pn" ] || continue
            # It must be one stage 2 considers done.
            #
            # A name removed from stage2.state is exactly a package whose
            # stage-2 artefact is no longer trusted -- that is what removing it
            # MEANS. Restoring it anyway undoes the fix that motivated the
            # removal, before the rebuild gets a chance to run.
            #
            # It happened twice, and the second time was invisible. The
            # filesystem package built in pass one predates the hook that adds
            # s390x's lib64 symlinks; restoring it REMOVED the symlink that
            # stage 1 had just installed, so /usr/lib64 was absent again and
            # the fix appeared not to work. binutils was the same shape and had
            # to be moved out of repo2 by hand -- which is a workaround for a
            # rule that was simply missing.
            #
            # pkgbase, not pkgname: stage2.state records what was BUILT, and a
            # split package like libxml2-docs is not in it under that name.
            pb=$(bsdtar -xOf "$f" .PKGINFO 2>/dev/null | sed -n 's/^pkgbase = //p')
            grep -qxF "${pb:-$pn}" "$STATE2" 2>/dev/null || continue
            # Installed, or named as a tool stage 2 has to supply itself.
            if ! grep -qxF "$pn" <<< "$inst"; then
                printf ' %s ' "${CHROOT_STAGE2_PKGS[*]}" | grep -q " $pn " || continue
            fi
            back+=("$f")
        done
        printf '  %s of %s stage-2 package(s) are installed and still trusted\n' \
            "${#back[@]}" "${#cand[@]}"
    fi
    if [ "${#back[@]}" -gt 0 ]; then
        sudo pacman --root "$ROOT" --config "$CONF" --cachedir "$CACHE" \
            --noconfirm --nodeps -U "${back[@]}" \
            > "$WORK/stage2-restore.txt" 2>&1 \
            || { tail -20 "$WORK/stage2-restore.txt" >&2; die "restoring stage-2 output failed"; }
        printf '  %s stage-2 package(s) restored\n' "${#back[@]}"
    fi
}

configure_chroot() {
    log "Configuring the chroot"
    # CARCH and CHOST, for the same reason they had to be set on the host --
    # except here the wrong value arrives from OUR OWN pacman package, which
    # ships Arch's /etc/makepkg.conf verbatim:
    #
    #   CARCH="x86_64"
    #   CHOST="x86_64-pc-linux-gnu"
    #
    # A stage-2 build with those would configure every source for x86_64 on an
    # s390x machine. CHOST must be the canonical triplet, not the Debian one:
    # config.sub turns s390x-linux-gnu into s390x-ibm-linux-gnu and GCC builds
    # its tree under the canonical name, which is what broke gcc's own
    # packaging on the host.
    sudo sed -i 's|^CARCH=.*|CARCH="s390x"|; s|^CHOST=.*|CHOST="s390x-ibm-linux-gnu"|' \
        "$ROOT/etc/makepkg.conf"
    sudo sed -i "s|^#\?MAKEFLAGS=.*|MAKEFLAGS=\"-j$(nproc)\"|" "$ROOT/etc/makepkg.conf"
    # !debug and !lto, matching what stage 1 used. Arch's defaults enable both;
    # turning them on here would change what is being compared between the two
    # stages, and comparing them is the whole point.
    sudo sed -i 's|^OPTIONS=.*|OPTIONS=(strip docs !libtool !staticlibs emptydirs zipman purge !debug !lto)|' \
        "$ROOT/etc/makepkg.conf"
    # CFLAGS and friends, which arrive from the same place and are just as
    # wrong. Our pacman package ships Arch's makepkg.conf verbatim, so the
    # chroot inherits
    #
    #   CFLAGS="-march=x86-64 -mtune=generic -O2 ... -fcf-protection ..."
    #
    # On s390x cc rejects that, and the failure surfaces nowhere near the
    # cause: meson simply cannot start.
    #
    #   libxml2/meson.build:1:0: ERROR: Unable to detect linker for compiler
    #   `cc -Wl,--version ... -march=x86-64 -mtune=generic ...`
    #
    # They are emptied rather than translated, because "no flags" is what stage
    # 1 used -- the host's makepkg.conf carries no CFLAGS line at all -- and
    # 179 working packages are the evidence that it builds. Choosing s390x
    # tuning (-march=z13, and only the hardening flags that exist on Z) is a
    # deliberate later step, not something to guess at inside a bootstrap.
    # TODO.md records it.
    #
    # APPENDED, not commented. The first attempt here put a # in front of each
    # assignment, and CFLAGS is a MULTI-LINE assignment: commenting its first
    # line left the continuations active and the quote unbalanced, so makepkg
    # would not start at all --
    #
    #   /etc/makepkg.conf: line 109: unexpected EOF while looking for matching `"'
    #
    # An override at the end of the file needs no parsing of what came before:
    # the last assignment is the one that counts.
    # A DROP-IN, not an append to makepkg.conf.
    #
    # Appending was wrong, and gcc is what proved it:
    #
    #   gfortran: error: unrecognized argument in option '-march=x86-64'
    #   configure: error: GNU Fortran is not working; please report a bug ...
    #
    # Arch splits makepkg.conf into /etc/makepkg.conf.d/*.conf, sourced AFTER
    # the main file. fortran.conf sets FFLAGS to the x86_64 list and FCFLAGS
    # from it; rust.conf does the same for RUSTFLAGS. So an override at the end
    # of makepkg.conf is itself overridden, silently, for exactly the variables
    # it does not mention -- CFLAGS survived only because no drop-in sets it.
    #
    # The error is worth noting for its shape: gcc reported that ITS OWN
    # freshly-built Fortran compiler "is not working", when the compiler was
    # fine and had been handed another architecture's flags. Everything about
    # the message points at the wrong thing.
    #
    # zz- so it sorts last: the drop-ins are read in glob order, and this has to
    # be the final word. Owned by no package, and remade on every run since
    # make_rootfs wipes the tree.
    sudo install -d -m0755 "$ROOT/etc/makepkg.conf.d"
    sudo tee "$ROOT/etc/makepkg.conf.d/zz-s390x.conf" > /dev/null <<'EOC'
# stage 2: every flag variable, because Arch's are x86_64's and the drop-ins
# under this directory would otherwise put them back.
CFLAGS="-march=z13 -mtune=z16 -O2 -pipe -fno-plt -fexceptions"
CXXFLAGS="$CFLAGS -Wp,-D_GLIBCXX_ASSERTIONS"
FFLAGS="$CFLAGS"
FCFLAGS="$CFLAGS"
LDFLAGS="-Wl,-O1 -Wl,--sort-common -Wl,--as-needed -Wl,-z,relro -Wl,-z,now"
LTOFLAGS=""
RUSTFLAGS=""
DEBUG_CFLAGS=""
DEBUG_CXXFLAGS=""
DEBUG_FFLAGS=""
DEBUG_FCFLAGS=""
DEBUG_RUSTFLAGS=""
EOC
    sudo grep -E '^(CARCH|CHOST|MAKEFLAGS|OPTIONS)=' "$ROOT/etc/makepkg.conf" | sed 's/^/  /'
    printf '  baseline: -march=z13 -mtune=z16, in makepkg.conf.d/zz-s390x.conf\n'
    # Named, because a drop-in that does not sort last does nothing and looks
    # like it worked.
    printf '  drop-ins read after it: %s\n' \
        "$(sudo ls "$ROOT/etc/makepkg.conf.d" | awk '$0 > "zz-s390x.conf"' | tr '\n' ' ')none"

    # --auto-features auto, for this chroot only.
    #
    # Our own meson package ships /usr/bin/arch-meson, and it passes
    # --auto-features enabled -- correct on Arch, whose build chroot has every
    # optional tool. Ours has none of them:
    #
    #   doxygen xsltproc asciidoctor itstool convert fig2dev elinks
    #   ducktype yelp-build        -- all ABSENT
    #
    # With `enabled`, each one is a hard error. libxml2 stops at
    #
    #   libxml2/doc/meson.build:3:10: ERROR: Program 'doxygen' not found
    #
    # MEASURED BEFORE CHOOSING, because building them was the other option and
    # it is not close: doxygen alone wants clang, fmt, spdlog and llvm-libs --
    # an entire compiler infrastructure for a documentation generator. Behind
    # the other eight stand Ruby, ImageMagick and a GNOME stack. That is
    # several times the size of everything built so far, for man pages.
    #
    # `auto` is meson's own default and means "build what you can". It is the
    # honest setting for an environment with fewer tools, not a workaround --
    # and what it drops is visible in the artefact, which is where this port
    # checks everything anyway.
    #
    # A WRAPPER, not a patched package: /usr/bin/arch-meson belongs to meson and
    # stage 2 must not ship a modified copy of it. meson takes the LAST
    # occurrence of an option, so appending wins while leaving every other
    # choice arch-meson makes intact. in_chroot puts /usr/local/bin first on
    # PATH so this is found.
    sudo install -d -m0755 "$ROOT/usr/local/bin"
    sudo tee "$ROOT/usr/local/bin/arch-meson" > /dev/null <<'EOW'
#!/usr/bin/env bash
# stage 2, two overrides, both appended because meson honours the last
# occurrence of an option.
#
#   --auto-features auto  This chroot has none of Arch's optional documentation
#                         tools, so a feature that cannot be built should be
#                         skipped rather than fatal.
#
#   --libdir lib          meson picks its default libdir by inspecting the
#                         system: 64-bit plus a REAL /usr/lib64 means "lib64".
#                         On Arch /usr/lib64 is a symlink, so it never triggers
#                         and arch-meson passes no --libdir at all. In here
#                         binutils had created a real /usr/lib64 (s390x's
#                         default MULTILIB_OSDIRNAME), so meson flipped, pkgconf
#                         installed there, and pkgconf COMPILED IN
#                         /usr/lib64/pkgconfig as its search path -- while every
#                         .pc file in the distribution is in /usr/lib/pkgconfig.
#                         Result: every pkg-config lookup in the chroot failed,
#                         reported by libxslt as a missing python-3.14 that was
#                         installed. binutils is pinned too; this is the
#                         backstop, because the heuristic will fire again the
#                         moment anything else creates that directory.
exec /usr/bin/arch-meson "$@" --auto-features auto --libdir lib
EOW
    sudo chmod 755 "$ROOT/usr/local/bin/arch-meson"
    printf '  arch-meson: wrapped with --auto-features auto, --libdir lib\n'

    # DNS. Four packages failed in prepare() on
    #
    #   fatal: unable to access 'https://github.com/...': Could not resolve
    #   host: github.com
    #   Failed to clone 'gl-mod/bootstrap' a second time, aborting
    #
    # m4, libtool, groff and libnghttp2 fetch git submodules -- gnulib and
    # friends -- and Arch's PKGBUILDs take their sources from git, so a chroot
    # that cannot resolve a name cannot start those builds at all. The retry
    # message is what makepkg prints; the reason is one line above it and easy
    # to miss.
    #
    # COPIED, not bind-mounted: a bind would break the moment the host's
    # resolv.conf is replaced (it is a systemd-resolved symlink here), and this
    # file is re-made on every run anyway because make_rootfs wipes the tree.
    sudo install -Dm644 /etc/resolv.conf "$ROOT/etc/resolv.conf" 2>/dev/null \
        || printf '  WARNING: no /etc/resolv.conf to copy; git submodules will fail\n'
    printf '  DNS: resolv.conf copied from the host\n'

    # makepkg refuses to run as root, so the chroot needs the SAME uid as the
    # user who owns the bind-mounted sources. A bind mount carries the host's
    # numeric owner across, so a different uid inside would see them as
    # somebody else's and fail to write $srcdir.
    sudo tee -a "$ROOT/etc/passwd" > /dev/null <<EOF
$BUILDER:x:$BUILD_UID:$BUILD_GID::/build:/usr/bin/bash
EOF
    sudo tee -a "$ROOT/etc/group" > /dev/null <<EOF
$BUILDER:x:$BUILD_GID:
EOF
    sudo mkdir -p "$ROOT/build" "$ROOT/repo2"
    sudo chown "$BUILD_UID:$BUILD_GID" "$ROOT/build" "$ROOT/repo2"
    # The stage-1 repository, so makepkg's --nodeps builds can still read the
    # packages if anything wants to, and so repo-add has somewhere to write.
    mkdir -p "$REPO2"
}

mount_chroot() {
    log "Mounting"
    # /dev/pts is not optional: without it any build step that opens a pty --
    # and gcc's testsuite driver does -- fails in a way that names the pty and
    # not the missing mount.
    for m in proc sys dev dev/pts; do
        sudo mkdir -p "$ROOT/$m"
    done
    mountpoint -q "$ROOT/proc"    || sudo mount -t proc  proc  "$ROOT/proc"
    mountpoint -q "$ROOT/sys"     || sudo mount -t sysfs sys   "$ROOT/sys"
    mountpoint -q "$ROOT/dev"     || sudo mount --bind /dev    "$ROOT/dev"
    mountpoint -q "$ROOT/dev/pts" || sudo mount -t devpts devpts "$ROOT/dev/pts"
    # Sources and PKGBUILDs, already fetched by stage 1. Bind-mounting them
    # means the chroot needs no network at all, which is worth having: this
    # host cannot reach dev.gnupg.org, and a build that silently re-fetches
    # would be a different build.
    mountpoint -q "$ROOT/build" || sudo mount --bind "$WORK/pkg" "$ROOT/build"
    mountpoint -q "$ROOT/repo2" || sudo mount --bind "$REPO2"    "$ROOT/repo2"
}

umount_chroot() {
    for m in repo2 build dev/pts dev sys proc; do
        mountpoint -q "$ROOT/$m" && sudo umount -l "$ROOT/$m"
    done
    return 0
}

# in_chroot <command...> -- run as the builder, with a sane environment.
in_chroot() {
    sudo chroot --userspec="$BUILD_UID:$BUILD_GID" "$ROOT" \
        /usr/bin/env -i \
        HOME=/build PATH=/usr/local/bin:/usr/bin \
        LC_ALL=C.UTF-8 \
        /usr/bin/bash -lc "$*"
}

# The CA bundle, which nothing else was going to create.
#
# Four packages -- m4, libtool, groff, libnghttp2 -- failed in prepare() on
#
#   Failed to clone 'gl-mod/bootstrap' a second time, aborting
#
# and the first diagnosis was DNS, correctly: the chroot had no resolv.conf.
# Copying it fixed resolution -- `getent hosts github.com` answers -- and the
# clones still failed, now on
#
#   fatal: unable to access 'https://...': error adding trust anchors from
#   file: /etc/ssl/certs/ca-certificates.crt
#
# Everything needed was already installed: the symlink, the Mozilla trust
# source, update-ca-trust, and p11-kit's trust. What was missing is that the
# bundle those produce is generated by an ALPM HOOK, and `pacman --root` does
# not run hooks -- so /etc/ca-certificates/extracted/tls-ca-bundle.pem, the
# target of that symlink, never existed. A dangling symlink and a complete
# installation look identical in a package list.
#
# Generated from OUR OWN trust source, not copied from the host: this is what
# will be on the target, and copying Ubuntu's bundle would be exactly the kind
# of host artefact the ARTEFACT check exists to find.
generate_ca_bundle() {
    log "Generating the CA bundle"
    # AS ROOT, not through in_chroot.
    #
    # in_chroot runs as the build user, and the first version of this used it.
    # update-ca-trust exited non-zero with
    #
    #   p11-kit: couldn't create file:
    #     /etc/ca-certificates/extracted/tls-ca-bundle.pem
    #
    # which is a permission error wearing the words of a broken tool. Writing
    # under /etc is root's job; makepkg is the only thing here that must not be
    # root.
    if sudo chroot "$ROOT" /usr/bin/env -i PATH=/usr/bin update-ca-trust \
            > "$WORK/stage2-ca.txt" 2>&1; then
        local n
        n=$(sudo grep -c "BEGIN CERTIFICATE" \
            "$ROOT/etc/ca-certificates/extracted/tls-ca-bundle.pem" 2>/dev/null || echo 0)
        # A count, because update-ca-trust exits 0 on an empty trust source and
        # the failure it hides is an https clone hours later.
        if [ "${n:-0}" -lt 50 ]; then
            printf '  WARNING: only %s certificates extracted; https will fail\n' "${n:-0}"
        else
            printf '  %s certificates\n' "$n"
        fi
    else
        printf '  WARNING: update-ca-trust failed, see %s\n' "$WORK/stage2-ca.txt"
    fi
}

smoke_test() {
    log "Smoke test: does the chroot build anything at all?"
    # NO PIPELINES IN THESE CHECKS. The first version ran `makeinfo --version |
    # head -1`, and $? came from head, so a perl that could not start was
    # reported as ok with its own error message as the version string. Same
    # shape as the `if build_package` bug that once reported "51 built, 0
    # failed" while four packages had failed. Each check runs one command and
    # its status is the command's.
    # HARD versus KNOWN-DRIFT, because they mean different things. A hard
    # check failing means the chroot cannot build and stage 2 must not start.
    # A drift check failing means a stage-1 package carries a host version
    # mismatch that STAGE 2 ITSELF repairs, by rebuilding that package before
    # the ones that need it. Treating the second as fatal would refuse to run
    # the very thing that fixes it.
    local drift="makeinfo"
    local ok=0 fail=0 noted=0
    while read -r desc cmd; do
        [ -n "$desc" ] || continue
        local out rc
        out=$(in_chroot "$cmd" 2>&1); rc=$?
        if [ "$rc" -eq 0 ]; then
            printf '  ok    %-12s %s\n' "$desc" "${out%%$'\n'*}"; ok=$((ok+1))
        elif [[ " $drift " == *" $desc "* ]]; then
            printf '  note  %-12s %s\n' "$desc" "${out%%$'\n'*}"; noted=$((noted+1))
        else
            printf '  FAIL  %-12s rc=%s %s\n' "$desc" "$rc" "${out%%$'\n'*}"; fail=$((fail+1))
        fi
    done <<'CHECKS'
bash bash --version
gcc gcc --version
ld ld --version
make make --version
makepkg makepkg --version
fakeroot fakeroot -- /usr/bin/id -u
bison bison --version
flex flex --version
perl perl -e 'print "perl $]\n"'
makeinfo makeinfo --version
compile cd /build && mkdir -p .stage2-smoke && cd .stage2-smoke && printf 'int main(void){return 0;}' > t.c && gcc t.c -o t && ./t && echo compiled-and-ran
CHECKS
    printf '\n  %s ok, %s failed, %s known drift\n' "$ok" "$fail" "$noted"
    if [ "$noted" -gt 0 ]; then
        cat <<'NOTE'

  makeinfo is the one expected failure, and it is what stage 2 exists for:
  texinfo was built against the HOST's perl 5.40 and our perl package is 5.42,
  so its XS module refuses to load ("Perl API version ... does not match").
  Rebuilding texinfo inside this chroot fixes it -- which is why texinfo has to
  come EARLY in the rebuild order, before gcc, glibc and binutils, all of which
  call makeinfo.
NOTE
    fi
    [ "$fail" -eq 0 ]
}


# Hooks that must NOT run in stage 2.
#
# Most stage-1 hooks are still right inside the chroot: the architectural ones
# (systemd's EFI, glibc's SFrame, gcc's multilib) describe s390x, and the
# host-absence ones (pam's fop, gnutls's leancrypto, krb5's ss) describe a
# build environment that has not changed. A few are no-ops here and harmless
# -- the libdir hooks insert a value meson would already have chosen.
#
# This list is for the ones that would actively BREAK. libgcrypt.sh extracts
# our libgpg-error into $WORK/stage1-prefix and injects that absolute host path
# into build(); the path does not exist in the chroot. It is also unnecessary
# there, because the chroot HAS our libgpg-error 1.61 installed, so
# /usr/bin/gpgrt-config is already the new one. That is stage 2 working as
# intended: the reason for the hook disappears.
# git.sh joins it for the same reason: it drops ZLIB_NG=1 because Ubuntu has no
# zlib-ng headers, and our own zlib-ng package ships them, so inside the chroot
# the flag is correct and the hook would be a downgrade.
# meson.sh joins them: it moves a wheel out of /usr/local, which only the
# host's Debian-patched python puts there.
# libarchive: stage 1 drops xar to break the bsdtar -> libxml2 -> libicuuc.so.76
# cycle. In here the versions agree, so build it as Arch does.
# Hoisted to the front of the stage-2 order.
#
# Stage 1's order is the real dependency closure and stage 2 keeps it -- but
# stage 1 had the HOST for its build tools, and a few of those tools are
# themselves in the list, sitting wherever their runtime dependencies put them.
# In the chroot the stage-1 copy is what is available, and for these it does
# not work:
#
#   texinfo -- binutils died on `make info-recursive`, and makeinfo says why:
#
#     Perl API version v5.40.0 of Texinfo::TreeElement does not match v5.42.0
#
#   Its XS module was compiled against the HOST's perl 5.40; our perl package
#   is 5.42. Every package that builds .info documentation -- binutils, gcc,
#   glibc, coreutils, gettext, m4 -- needs makeinfo, and texinfo sits near the
#   end of the list because that is where its own dependencies are. Rebuilding
#   it in here against our perl fixes it, which is the entire point of stage 2;
#   it just has to happen first.
#
# Duplicates need no handling: these names appear again later in
# STAGE1_PACKAGES, and rebuild() skips anything already in stage2.state. The
# list is prepended rather than reordered, so stage 1's order stays the single
# statement of the closure.
#   libxslt -- shadow died on `configure: error: xsltproc is missing.` and
#   libxslt cannot be built on the host: its configure demands libxml2 2.15.1
#   and Ubuntu ships 2.14.5. Ours is 2.15.3 and lives only in here, so this is
#   the only place libxslt can come from -- built by stage 2, not installed
#   into it. It has to precede shadow, which the list order does not do.
#
#   binutils, then pkgconf -- in that order, and both before anything that uses
#   pkg-config. Stage 1's repository is clean of /usr/lib64; the stage-2
#   binutils build created it, because s390x's default MULTILIB_OSDIRNAME is
#   lib64. meson then chose lib64 as its default libdir (it inspects the system,
#   and a REAL /usr/lib64 flips it -- Arch's is a symlink), pkgconf installed
#   there, and pkgconf compiled in /usr/lib64/pkgconfig as its search path while
#   every .pc in the distribution sits in /usr/lib/pkgconfig. Every pkg-config
#   lookup in the chroot then failed. binutils first so the directory is gone
#   before pkgconf builds; the arch-meson wrapper pins --libdir lib as the
#   backstop.
#
#   libxml2 -- because the xar cycle reformed INSIDE stage 2. libarchive is in
#   a hook that runs at stage 1 only, so stage 2 rebuilt it as Arch does, with
#   libxml2 that happened to be installed at that moment: the stage-1 one, which
#   wants the host's libicuuc.so.76. bsdtar then could not start, and bsdtar is
#   what makepkg uses to extract sources and write packages -- so 39 of 39
#   packages failed on the same line, including libxml2 itself. The stage-1 fix
#   (drop xar) does not reach in here.
#
#   The way out needs no new mechanism: libarchive is dropped from stage2.state,
#   which makes the restore fall back to the stage-1 build that has no xar and
#   therefore no libxml2 at all. bsdtar starts, libxml2 gets rebuilt against our
#   icu 78, and libarchive is rebuilt later in the list -- with xar, against a
#   libxml2 whose ICU now agrees.
#
#   wget -- five packages died on
#
#     wget: error while loading shared libraries: libnettle.so.8
#
#   Our nettle ships .9; .8 is Ubuntu's. coreutils, sed, grep, findutils and
#   diffutils all fetch their translation catalogues with wget in prepare(), so
#   a wget that cannot start stops them before they compile a line. Exactly the
#   bsdtar shape: a stage-1 TOOL linked against the host, which only matters
#   once it is the tool actually being used.
#
#   the Python packaging set -- brotli, libseccomp and meson build wheels with
#   `python -m build`, which did not exist in the chroot. Building it means
#   running it, and its dependencies close the same circle. Arch's PKGBUILDs
#   carry _bootstrap=1 for exactly this, and it must run in HERE rather than on
#   the host, whose python would bake dist-packages into every one of them.
STAGE2_FIRST=(texinfo libxml2 binutils pkgconf wget libxslt
              python-packaging python-pyproject-hooks python-build
              python-installer python-setuptools python-wheel
              python-setuptools-scm python-markupsafe python-jinja)

# Packages the chroot needs that can only come from repo2.
#
# The restore puts back stage-2 builds of what is ALREADY INSTALLED, which is
# right for everything the stage-1 closure provides and silently wrong for
# anything stage 2 introduces. libxslt is the case: it cannot be built on the
# host at all, so it is absent from repo1, so it is never installed, so the
# restore skips it -- while stage2.state says it is done and rebuild() reports
#
#   == libxslt already rebuilt, skipping ==
#
# and shadow keeps failing on `xsltproc is missing`. Built, recorded, and
# nowhere to be found.
#
# Named explicitly rather than inferred. The obvious generalisation -- restore
# everything trusted, installed or not -- brings back zlib-ng-compat, which
# conflicts with the zlib stage 1 chose for this chroot. A list says which
# packages are build tools and why; a conflict heuristic would have to be
# extended every time a package like that appeared.
# Packages a REPOSITORY can hold and a SYSTEM cannot: alternatives to something
# else in there. zlib-ng-compat replaces zlib, and stage 1 chose zlib for this
# chroot. Excluded by name rather than discovered by conflict, so populate stays
# deterministic -- and if a new one appears, pacman names the pair and the
# fallback says so out loud.
# What a REPOSITORY can hold and a SYSTEM cannot. Found by installing the whole
# repository into a probe root and excluding whatever pacman objected to, until
# it stopped objecting -- four names out of 190, and 186 packages install.
#
# `-Syp` was not enough to find them. It resolves dependencies and says nothing
# about FILE conflicts, so the first list came back clean and the real install
# still failed. Two of these were only visible to an actual install.
CHROOT_EXCLUDE=(
    zlib-ng-compat      # replaces zlib; stage 1 chose zlib for this chroot
    git-zsh-completion  # requires zsh, which this port does not build. A shell
                        # completion file, not a build tool.
    libcurl-compat      # both ship /usr/lib/libcurl.la, so they collide with
    libcurl-gnutls      # curl itself. ABI-compatibility builds of libcurl; a
                        # build chroot needs neither.
)

CHROOT_STAGE2_PKGS=(
    libxslt
    # The Python packaging set, for the same reason and a sharper one: their
    # package() computes install paths from the RUNNING python.
    #
    #   local site_packages=$(python -c "import site; print(site.getsitepackages()[0])")
    #   rm "$pkgdir/$site_packages/$_name"/*.exe
    #
    # On the host that resolves to Debian's dist-packages, so three of them
    # failed on `rm` finding nothing -- and the three that SUCCEEDED shipped
    # usr/lib/python3/dist-packages, where our python 3.14 never looks. 180
    # paths of unreachable modules, and nothing about them looked wrong.
    #
    # The failures were protective. That is the useful lesson here: those three
    # refused rather than shipping the same fiction, and the ARTEFACT check --
    # which only ever asked about C library directories -- has been taught
    # dist-packages so it can say so next time.
    python-packaging python-pyproject-hooks python-build
    python-installer python-setuptools python-wheel
    python-setuptools-scm
    python-markupsafe python-jinja
)

# Packages whose sources must be extracted on the HOST, because the chroot
# cannot extract anything until they are rebuilt.
#
# THE CYCLE. makepkg extracts with bsdtar. bsdtar is libarchive, libarchive
# links libxml2 for xar support, and the stage-1 libxml2 was linked against the
# HOST's ICU 76 while our icu package ships ICU 78:
#
#   bsdtar: error while loading shared libraries: libicuuc.so.76
#
# So nothing unpacks in the chroot until libxml2 is rebuilt, and libxml2 cannot
# unpack in the chroot. One of the nine soname drifts, turned into a bootstrap
# cycle by the one tool that has to work first.
#
# Extraction is not compilation, so doing it outside is less of an impurity
# than it looks -- the host's bsdtar unpacks a tarball byte for byte. What DOES
# leak is prepare(), which `makepkg -o` also runs: mostly patching, but where
# it runs autoreconf the generated configure carries the host's autotools.
# That is why this is a LIST and not the default. Once libxml2 is rebuilt,
# bsdtar works and everything after it extracts in the chroot.
# wget joins libxml2 here for a reason worth stating: it cannot rebuild itself.
#
#   Fetching gnulib PO files from https://translationproject.org/latest/
#   wget: error while loading shared libraries: libnettle.so.8
#
# gnulib's bootstrap fetches translation catalogues WITH wget, and the stage-1
# wget links libnettle.so.8 directly -- Ubuntu's soname, where ours is .9. Our
# gnutls is already a stage-2 package and correctly wants .9; wget is the only
# thing left holding the old one, and the tool it needs to fix itself is itself.
#
# The host has a working wget, so it runs prepare() and does the fetching
# (makepkg -o); the chroot then compiles and links against our nettle (-e).
# Five more packages -- coreutils, sed, grep, findutils, diffutils -- fetch PO
# files the same way and are unblocked by this one rebuild, which is why wget is
# also hoisted into STAGE2_FIRST.
STAGE2_HOST_EXTRACT=(libxml2 wget)

host_extract() {
    local n="$1" h
    for h in "${STAGE2_HOST_EXTRACT[@]}"; do [ "$n" = "$h" ] && return 0; done
    return 1
}

# stage2_build <name> -- rebuild one package inside the chroot and install it.
#
# The hook is applied on the HOST, not in the chroot: hooks are seds over the
# PKGBUILD, and /build is the same directory seen from both sides, so the
# patched file is what makepkg reads. Nothing needs to be duplicated inside.
stage2_build() {
    local name="$1"
    local dir="$WORK/pkg/$name"
    [ -d "$dir" ] || { echo "  no checkout for $name" >&2; return 1; }

    ( cd "$dir" && git checkout -- PKGBUILD 2>/dev/null ) || true
    if [ -f "$PATCH_DIR/$name.sh" ]; then
            # EL_STAGE=2, and no skip list any more.
            #
            # There WAS a list -- naming hooks to ignore here. It skipped the
            # whole FILE, and that broke silently the moment a listed hook grew a
            # section both stages need: git and meson each kept failing in stage
            # 2 on exactly what their new sections fix, while the log said
            # "hook skipped (stage-1 only)" about a hook that was by then two
            # thirds relevant.
            #
            # A list of file names cannot say why. The hooks read EL_STAGE and
            # decide per section, with the reason written beside the guard.
            ( cd "$dir" && EL_STAGE=2 bash "$PATCH_DIR/$name.sh" ) || {
                echo "  hook failed" >&2; return 1; }
            # A hook can leave a PKGBUILD that no longer parses, and makepkg
            # reports that far from its cause:
            #
            #   /build/binutils/PKGBUILD: line 107: --enable-plugins:
            #     command not found
            #
            # binutils' hook had commented out one option of a
            # backslash-continued ./configure, which does not remove an option
            # -- it breaks the continuation, and the next option becomes a
            # command. Checking here names the hook that did it.
            #
            # -O extglob because PKGBUILDs use it (`rm -r !(test)`), and bash -n
            # calls a valid file broken without it.
            ( cd "$dir" && bash -O extglob -n PKGBUILD ) || {
                echo "  hook left an unparseable PKGBUILD" >&2; return 1; }
    fi

    ( cd "$dir" && rm -f ./*.pkg.tar.* ) || true
    # NO --nocheck. Stage 1 skipped the test suites because they ran against
    # the host's libraries and their verdict said nothing about the port. Here
    # they test what was actually built, which is the whole point of stage 2.
    local mkflags="--nodeps --ignorearch --skippgpcheck --skipchecksums"
    # EL_NOCHECK=1 for the FIRST pass over the list, and only that.
    #
    # Stage 1 skipped every test suite because it ran against the host's
    # libraries, so its verdict said nothing about the port. In here a suite
    # tests what was actually built, which is worth having -- but not on the
    # pass whose job is to find out whether a hundred and thirty-three packages
    # can be rebuilt at all. glibc's suite alone is longer than most of the
    # builds around it, and a suite is the likeliest place in a build to wait
    # forever on a tty or a socket.
    #
    # So: one pass to get a complete stage-2 repository, then the suites, then
    # stage 3 -- where they run on a self-hosted toolchain and their verdict is
    # about the port rather than about the bootstrap. Off by default is wrong
    # here; this must be asked for.
    [ "${EL_NOCHECK:-0}" = "1" ] && mkflags="$mkflags --nocheck"
    if host_extract "$name"; then
        echo "  extracting on the host (chroot bsdtar not usable yet)"
        ( cd "$dir" && LC_ALL=C.UTF-8 makepkg $mkflags -o -C -f ) || return 1
        # -e: build in the tree already there. -C would wipe it again.
        in_chroot "cd /build/$name && makepkg $mkflags -e -f" || return 1
    else
        in_chroot "cd /build/$name && makepkg $mkflags -C -f" || return 1
    fi

    # An exit code is not proof. Only the artefact is.
    local produced=()
    shopt -s nullglob; produced=("$dir"/*.pkg.tar.*); shopt -u nullglob
    [ "${#produced[@]}" -gt 0 ] || { echo "  no package produced" >&2; return 1; }

    cp -f "${produced[@]}" "$REPO2/" || return 1
    local names=() f
    for f in "${produced[@]}"; do names+=("$(basename "$f")"); done
    ( cd "$REPO2" && repo-add core.db.tar.gz "${names[@]}" ) > /dev/null || return 1

    # Install into the chroot so the NEXT package builds against it. With the
    # host's pacman and --root, because the chroot's own pacman does not start
    # until stage 2 has rebuilt it.
    #
    # --nodeps, and ONLY here. The first rebuilt package would not install:
    #
    #   unable to satisfy dependency 'libicuuc.so=78-64' required by libxml2
    #
    # Both halves of that are correct. This chroot runs makepkg's soname scan,
    # so a package built in here declares versioned soname dependencies the way
    # Arch's really do -- which is the faithful metadata stage 2 exists to
    # produce. The stage-1 packages around it were built on the host under
    # !autodeps, so our icu ships no `provides = libicuuc.so=78-64` to match.
    #
    # For the length of stage 2 the chroot is therefore a MIXED POPULATION:
    # some packages describe their dependencies in Arch's terms and some in
    # names only. No resolver can satisfy that, and none should be asked to --
    # it is a property of a bootstrap halfway through, not of the output. It
    # dissolves on its own as the last package is rebuilt.
    #
    # What is NOT relaxed is the metadata in the packages: they keep their
    # versioned depends, and test-chroot.sh's RESOLVE check runs the resolver
    # against the finished repository with --nodeps OFF. The relaxation is one
    # install command wide, and the check that would catch its consequences is
    # still there.
    sudo pacman --root "$ROOT" --config "$CONF2" --cachedir "$CACHE" \
        --noconfirm --nodeps -U "${produced[@]}" > "$WORK/stage2-inst-$name.txt" 2>&1 || {
        tail -10 "$WORK/stage2-inst-$name.txt" >&2; return 1; }
    printf '  installed %s package(s)\n' "${#produced[@]}"

    # Clean up, but only now, and only because it worked.
    #
    # A hundred and thirty-three source trees plus their pkg/ staging do not fit
    # on this disk. Filling it is not a hypothetical here: it happened once, and
    # what it looked like was not "no space" -- it was I/O errors from unrelated
    # virtual machines on the same host. Cheap to prevent, expensive to explain.
    #
    # AFTER the install, so nothing is thrown away until the package is proven
    # to exist and to install. NOT on failure -- src/ and pkg/ are the whole
    # evidence of what went wrong, and a build that failed is exactly the one
    # worth looking at. makepkg -c would delete them either way.
    #
    # Only makepkg's own two directories, and only inside this package's
    # checkout. The git tree, the PKGBUILD, the downloaded sources and the built
    # package are all left alone.
    ( cd "$dir" && rm -rf src pkg ) || true
}

# A pacman.conf that sees BOTH repositories: stage 2's output first, so a
# rebuilt package wins, and stage 1 behind it for everything not yet redone.
write_conf2() {
    cat > "$CONF2" <<EOF
[options]
Architecture = s390x
SigLevel = Never
[stage2]
Server = file://$REPO2
[core]
Server = file://$REPO1
EOF
}

rebuild() {
    write_conf2
    mkdir -p "$REPO2"
    local ok=0 fail=0 rc=0 failed=()
    for p in "$@"; do
        if grep -qxF "$p" "$STATE2" 2>/dev/null; then
            echo "== $p already rebuilt, skipping =="; continue
        fi
        # Per package, not once at the start. The run is long enough that the
        # disk state at the end has nothing to do with the disk state when it
        # was checked, and the failure mode is not local to this script.
        space_ok || { echo "== stage 2: stopping, disk too low =="; break; }
        log "stage 2: $p"
        # watched, not a plain call: see bootstrap-pacman.sh. A hundred and
        # thirty-three packages is far too many to sit in front of, and one
        # silent build would hold the whole run.
        if watched "$WORK/stage2-log-$p.txt" stage2_build "$p"; then
            echo "$p" >> "$STATE2"; ok=$((ok + 1)); echo "OK    $p"
        else
            rc=$?
            fail=$((fail + 1)); failed+=("$p")
            if [ "$rc" -eq 2 ]; then
                echo "STALL $p  (no output for ${EL_STALL_MIN:-45} min, killed)"
            else
                echo "FAIL  $p  (see $WORK/stage2-log-$p.txt)"
            fi
            tail -5 "$WORK/stage2-log-$p.txt" | sed 's/^/      /'
        fi
    done
    echo
    echo "== stage 2: $ok rebuilt, $fail failed =="
    [ "$fail" -eq 0 ] || printf '  failed: %s\n' "${failed[*]}"
}

main() {
    require_space
    [ -f "$REPO1/core.db.tar.gz" ] || die "no stage-1 repository at $REPO1"
    trap umount_chroot EXIT
    make_rootfs
    configure_chroot
    mount_chroot
    generate_ca_bundle
    smoke_test || die "the chroot cannot build; stage 2 stops here"
    log "Chroot ready"
    if [ "$#" -eq 0 ]; then
        echo "  enter it with:"
        echo "    sudo chroot --userspec=$BUILD_UID:$BUILD_GID $ROOT /usr/bin/bash -l"
        echo "  or rebuild packages:"
        echo "    bash $0 texinfo perl m4 autoconf ..."
        echo "    bash $0 --all      # all ${#STAGE1_PACKAGES[@]}, in order"
        return 0
    fi
    touch "$STATE2"
    # --all: the shared list, in its order. Typing a hundred and thirty-three
    # names is not a workflow, and typing a subset of them is how an ordering
    # gets quietly reinvented.
    if [ "$1" = "--all" ]; then
        rebuild "${STAGE2_FIRST[@]}" "${STAGE1_PACKAGES[@]}"
    else
        rebuild "$@"
    fi
}

main "$@"
