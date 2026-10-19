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

# WHICH STAGE THIS RUN IS. Stage 2 rebuilds stage 1's output against itself;
# stage 3 does the same to stage 2's, and the port is self-hosting when stage 3
# reproduces stage 2. The machinery is identical -- what changes is WHERE the
# chroot is populated from and WHERE the result lands, so it is one variable
# and not a second script:
#
#   STAGE_N=3 bash scripts/build-stage2.sh --all
#
# The hooks need nothing: all four ask whether EL_STAGE is 1, and 3 is not 1,
# exactly as 2 is not.
STAGE_N="${STAGE_N:-2}"
[ "$STAGE_N" -ge 2 ] 2>/dev/null || { echo "STAGE_N must be 2 or more" >&2; exit 1; }
# Stage 2 reads the stage-1 repository, which is named `repo`; every stage
# after it reads the one numbered below it.
if [ "$STAGE_N" = 2 ]; then _prev_repo="repo"; else _prev_repo="repo$((STAGE_N - 1))"; fi

REPO1="${REPO1:-$WORK/$_prev_repo/s390x}"
REPO2="${REPO2:-$WORK/repo$STAGE_N/s390x}"
ROOT="${ROOT:-$WORK/rootfs-stage$STAGE_N}"
CONF="${CONF:-$WORK/pacman-stage$STAGE_N.conf}"
CACHE="${CACHE:-$WORK/pacman-stage$STAGE_N.cache}"
CONF2="${CONF2:-$WORK/pacman-stage$STAGE_N-both.conf}"
STATE2="${STATE2:-$WORK/stage$STAGE_N.state}"
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
    # The Python packaging tools, and STAGE 3 IS WHAT REVEALED THEM. Every
    # python-* package is built with them, and none of them declares that they
    # must already be in the chroot -- at stage 2 they were, because stage 1
    # had left them and the restore put them back each run. A chroot populated
    # from stage 2 alone starts without them, and the failure is circular:
    #
    #   python-setuptools: Cannot import 'setuptools.build_meta'
    #
    # setuptools is built with setuptools. Naming them here is what makes the
    # chroot reproducible rather than inherited.
    python python-setuptools python-build python-installer python-wheel
    python-flit-core python-packaging
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
    #   tcl       sqlite, dont le build appelle tclsh
    #   libsodium openldap, dont le configure cherche sodium.h et s'arrete
    #             sur « --enable_argon2=yes requires --with-argon2 »
    #   unixodbc  openldap encore, qui le declare en makedepends
    #
    # tcl dit aussi pourquoi cette liste existe plutot que de compter sur ce
    # qui a deja ete bati. Il EST construit par l'etage 2, et il avait bien
    # ete installe dans le chroot -- mais la passe suivante RECREE ce chroot,
    # qui ne reprend que CHROOT_PKGS et ce que la restauration ramene. Un
    # outil de construction bati en cours de route disparait donc a la
    # relance, et sqlite s'arrete sur « tclsh: command not found » alors que
    # tcl est dans repo2. Ce qu'une recette appelle doit etre nomme ici, et
    # non herite d'une passe anterieure.
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
    gperf wget patchelf inetutils swig help2man tcl libsodium unixodbc
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
    log "Populating the stage-$STAGE_N rootfs from stage $((STAGE_N - 1))"
    cat > "$CONF" <<EOF
[options]
Architecture = s390x
SigLevel = Never
[core]
Server = file://$REPO1
EOF
    # NOTHING MAY BE MOUNTED UNDER $ROOT WHEN THIS RUNS.
    #
    # `rm -rf` follows a bind mount and deletes what is on the other side. This
    # function had no such guard, and the cost was the host's /dev: a diagnostic
    # session left `mount --rbind /dev "$ROOT/dev"` in place, the next run wiped
    # the rootfs, and the delete went through the mount into the real /dev. Every
    # device node went -- zero, full, random, urandom, tty, console -- and
    # /dev/null came back later as a regular file created by a redirection, which
    # broke every `> /dev/null` on the machine.
    #
    # Two guards, because the first one is not enough: unmount, then CHECK, then
    # refuse. A stale mount is a reason to stop, never a thing to delete through.
    umount_chroot
    if findmnt -rno TARGET | grep -qF "$ROOT/"; then
        printf 'still mounted under %s:\n' "$ROOT" >&2
        findmnt -rno TARGET | grep -F "$ROOT/" | sed 's/^/  /' >&2
        die "refusing to rm -rf through a mount"
    fi
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
            --noconfirm -Sy "${all[@]}" > "$WORK/stage$STAGE_N-install-full.txt" 2>&1; then
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
            "$WORK/stage$STAGE_N-install-full.txt" | sed 's/^/    /' | cut -c1-100 | head -6
        printf '  falling back to CHROOT_PKGS (see stage2-install-full.txt)\n'
        sudo pacman --root "$ROOT" --config "$CONF" --cachedir "$CACHE" \
            --noconfirm -Sy "${CHROOT_PKGS[@]}" > "$WORK/stage$STAGE_N-install.txt" 2>&1 \
            || { tail -20 "$WORK/stage$STAGE_N-install.txt" >&2; die "populate failed"; }
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
    # --nodeps TWICE, which is not a typo. pacman documents it: `-d` skips
    # dependency VERSION checks, `-dd` skips dependency checks entirely. With
    # one, cython could not be installed --
    #
    #   warning: cannot resolve "python-pygments", a dependency of "cython"
    #   :: unable to satisfy dependency 'python-numpy' required by cython
    #
    # -- and the numbers matter: cython is wanted here only as a BUILD tool for
    # libseccomp's Python binding, and its declared runtime dependencies are
    # numpy and pygments. numpy brings BLAS and LAPACK. A single -d looked like
    # it was skipping dependencies and was only skipping their versions, which
    # nearly bought an entire numerical stack to compile one .pyx file.
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
    # UNE SEULE VERSION PAR PAQUET, LA PLUS RECENTE.
    #
    # repo-add tient la base a jour, mais le FICHIER de l'ancienne version
    # reste sur le disque : un paquet rebati a un pkgver different laisse deux
    # archives cote a cote. La liste ci-dessus les ramasse toutes les deux, et
    # pacman refuse le lot entier :
    #
    #   error: '.../python-rpds-py-<ancienne>.pkg.tar.zst': duplicate target
    #
    # Un seul doublon suffit a faire echouer la restauration, donc le demarrage
    # de l'etage 2. Garder la plus recente par pkgname est ce que la base fait
    # deja de son cote.
    local back=() inst f pn
    local -A newest=()
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
            # A package that cannot coexist with what is installed must not
            # come back by ANY route. Stated here rather than relied upon:
            # today every CHROOT_EXCLUDE name also exists in repo1, so the
            # test below would have caught them, but that is an accident of
            # the current repository and not a rule.
            if printf ' %s ' "${CHROOT_EXCLUDE[*]}" | grep -q " $pn "; then
                continue
            fi
            # Installed, or a LEAF repo1 never had, or named outright.
            #
            # THE MIDDLE CASE WAS MISSING, and it cost a twenty-minute rust
            # build. libgit2, numactl, liburing, docbook-xml and docbook-xsl
            # exist only in repo2: this port never built them at stage 1. So
            # the populate step cannot install them, so `$inst` never names
            # them, so they were dropped at the next make_rootfs -- an hour
            # after they had built cleanly. rust then stopped on
            #
            #   pkg-config --libs --cflags libgit2 'libgit2 >= 1.9.4'
            #   Package libgit2 was not found in the pkg-config search path.
            #
            # Naming those five in CHROOT_STAGE2_PKGS would have worked, and
            # would have set the same trap for the sixth. A package repo1 does
            # not have cannot DISPLACE anything by being restored, and
            # displacement is the entire worry that list arbitrates -- so it
            # comes back unconditionally. The list keeps what it is actually
            # for: repo1 has the package, and the repo2 build must win anyway.
            if ! grep -qxF "$pn" <<< "$inst"; then
                if compgen -G "$REPO1/$pn-[0-9]*.pkg.tar.*" >/dev/null; then
                    printf ' %s ' "${CHROOT_STAGE2_PKGS[*]}" | grep -q " $pn " || continue
                fi
            fi
            if [ -n "${newest[$pn]:-}" ] && [ "${newest[$pn]}" -nt "$f" ]; then
                continue
            fi
            newest["$pn"]="$f"
        done
        back=("${newest[@]}")
        printf '  %s of %s stage-2 package(s) are installed and still trusted\n' \
            "${#back[@]}" "${#cand[@]}"
    fi
    if [ "${#back[@]}" -gt 0 ]; then
        sudo pacman --root "$ROOT" --config "$CONF" --cachedir "$CACHE" \
            --noconfirm --nodeps --nodeps -U "${back[@]}" \
            > "$WORK/stage$STAGE_N-restore.txt" 2>&1 \
            || { tail -20 "$WORK/stage$STAGE_N-restore.txt" >&2; die "restoring stage-2 output failed"; }
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
    # SOURCES KEPT, BECAUSE UPSTREAMS GO AWAY.
    #
    # makepkg downloads into the recipe directory and the chroot is torn down
    # after every pass, so each tarball is fetched and discarded. The port then
    # depends, for ever, on every upstream still serving the same bytes at the
    # same URL. One already does not:
    #
    #   libaio: curl: (22) The requested URL returned error: 404
    #
    # upstream.lock pins the RECIPE commit, which protects reproducibility and
    # freezes a URL at the same time. Only a copy of the bytes closes that.
    #
    # /build is the bind mount shared with the host, so a source written there
    # outlives the chroot. One directory for every package and every stage:
    # makepkg skips a download whose checksum already matches, which makes the
    # second pass faster as a side effect rather than as the point.
    sudo install -d -o "$BUILD_UID" -g "$BUILD_GID" "$ROOT/build/.sources"
    sudo sed -i 's|^#\?SRCDEST=.*|SRCDEST=/build/.sources|' "$ROOT/etc/makepkg.conf"
    grep -q '^SRCDEST=' "$ROOT/etc/makepkg.conf" ||
        echo 'SRCDEST=/build/.sources' | sudo tee -a "$ROOT/etc/makepkg.conf" >/dev/null
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
    # DownloadUser, which the rebuilt pacman brings with it. nss failed on
    #
    #   error: problem setting DownloadUser 'alpm' (user does not exist)
    #   ==> ERROR: 'pacman' returned a fatal error (1)
    #
    # Arch's pacman.conf drops privileges to `alpm` for downloads, and that user
    # exists on a real Arch system because the package creates it via sysusers.d
    # -- which `pacman --root` does not run, the same reason the CA bundle was
    # never generated. Nothing in this chroot downloads anything (every source is
    # already in /build, every package installed with -U from a local file), so
    # the setting has no purpose here and its absence is fatal only because
    # pacman checks it at startup.
    if [ -f "$ROOT/etc/pacman.conf" ]; then
        sudo sed -i 's/^\s*DownloadUser/#DownloadUser/' "$ROOT/etc/pacman.conf"
        sudo grep -q '^#DownloadUser' "$ROOT/etc/pacman.conf" &&
            printf '  pacman: DownloadUser disabled (no such user in a chroot)\n'
    fi

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
    for m in proc sys dev; do
        sudo mkdir -p "$ROOT/$m"
    done
    mountpoint -q "$ROOT/proc"    || sudo mount -t proc  proc  "$ROOT/proc"
    mountpoint -q "$ROOT/sys"     || sudo mount -t sysfs sys   "$ROOT/sys"
    # /dev by --rbind, then --make-rslave. Not a plain --bind, and nothing under
    # it is ever modified.
    #
    # A plain --bind does NOT carry submounts, so the chroot saw /dev/shm as the
    # empty 0755 stub inside devtmpfs rather than the host's tmpfs. That cost
    # three passes: CPython runs sem_open at configure time, got EACCES, decided
    # the platform has no POSIX semaphores, and compiled _multiprocessing without
    # SemLock -- after which every consumer failed with a message blaming the
    # platform, days after the cause.
    #
    # The first fix mounted a separate tmpfs at $ROOT/dev/shm and chmod'ed it.
    # That was wrong in a way worth recording: $ROOT/dev was a bind of the HOST's
    # /dev, so writes under it reach the real /dev -- and the host's /dev/null
    # ended up replaced by a regular file, which broke every redirection on the
    # machine until it was recreated with mknod.
    #
    # --rbind brings the host's /dev/shm along as it is: already a tmpfs, already
    # drwxrwxrwt. Nothing to create, nothing to chmod, nothing of the host's to
    # touch. --make-rslave then stops any mount this chroot makes from
    # propagating back out.
    mountpoint -q "$ROOT/dev" || {
        sudo mount --rbind /dev "$ROOT/dev"
        sudo mount --make-rslave "$ROOT/dev"
    }
    # PROVED from inside, as the build user. Every earlier check of this was made
    # as root and passed while the build kept failing.
    if ! sudo chroot --userspec="$BUILD_UID:$BUILD_GID" "$ROOT" \
            /usr/bin/env -i PATH=/usr/bin sh -c \
            'f=/dev/shm/.el-probe.$$; : > "$f" && rm -f "$f"'; then
        die "/dev/shm is not writable by the build user; python would build without POSIX semaphores"
    fi
    # Sources and PKGBUILDs, already fetched by stage 1. Bind-mounting them
    # means the chroot needs no network at all, which is worth having: this
    # host cannot reach dev.gnupg.org, and a build that silently re-fetches
    # would be a different build.
    # THE SOURCE OF THE BIND HAS TO EXIST, and on a machine that never ran
    # stage 1 it does not. The mount then fails, /build stays empty inside the
    # chroot, and every package dies on
    #
    #   /usr/bin/bash: line 1: cd: /build/<name>: No such file or directory
    #
    # which names the chroot's empty directory and not the missing host one.
    # The recipes are cloned into $WORK/pkg later, so the directory is created
    # here rather than assumed inherited from an earlier stage.
    mkdir -p "$WORK/pkg"
    mountpoint -q "$ROOT/build" || sudo mount --bind "$WORK/pkg" "$ROOT/build" \
        || die "cannot bind $WORK/pkg onto $ROOT/build"
    mountpoint -q "$ROOT/repo2" || sudo mount --bind "$REPO2"    "$ROOT/repo2" \
        || die "cannot bind $REPO2 onto $ROOT/repo2"
}

umount_chroot() {
    # -R for dev, because --rbind brought its submounts with it.
    mountpoint -q "$ROOT/dev" && sudo umount -R -l "$ROOT/dev"
    for m in repo2 build sys proc; do
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
# The package scriptlets, which `pacman --root` never ran either.
#
# THE SYMPTOM was a postgresql build that stopped nine minutes in on
#
#   postgres.sgml:22: I/O error : failed to load
#   "http://www.oasis-open.org/docbook/xml/4.5/docbookx.dtd"
#
# with docbook-xml INSTALLED and /etc/xml/docbook-xml present on disk. What was
# missing is /etc/xml/catalog -- the ROOT catalog that delegates to it -- which
# the package's own post_install creates. generate_ca_bundle below exists
# because `pacman --root` does not run ALPM HOOKS. Scriptlets turn out to be
# the same story one layer down, and the port had only learned half of it.
#
# WHY THIS RUNS UPSTREAM SCRIPT rather than writing the catalog by hand: the
# entries are version-dependent -- docbook-xsl registers a delegate per release
# series, docbook-xml one per DTD version -- so a hand-copied list goes stale
# the first time Arch bumps either. The scriptlet is already on disk in the
# local database. Running it is shorter AND more correct.
#
# Safe to run every time: make_rootfs rebuilds the chroot on each invocation,
# so this always meets a fresh /etc and cannot accumulate duplicate entries.
run_scriptlets() {
    local sl base name ver ran=0 failed=0 failed_names=""
    for sl in "$ROOT"/var/lib/pacman/local/*/install; do
        [ -f "$sl" ] || continue
        base=${sl%/install}; base=${base##*/}
        # base is name-pkgver-pkgrel; post_install wants pkgver-pkgrel.
        ver=${base##*-}
        name=${base%-*}
        ver="${name##*-}-$ver"
        if sudo chroot "$ROOT" /usr/bin/env -i PATH=/usr/bin \
                /usr/bin/bash -c ". /var/lib/pacman/local/$base/install
                    declare -f post_install >/dev/null || exit 0
                    post_install '$ver'" >/dev/null 2>&1; then
            ran=$((ran + 1))
        else
            # A COUNT IS NOT A DIAGNOSIS. This said "3 scriptlet(s) run, 1
            # failed" and threw the output away, so the one that failed had
            # no name and no message -- and its effect (a missing system
            # user, an empty CA bundle) surfaced much later, elsewhere.
            failed=$((failed + 1))
            failed_names="$failed_names $name"
        fi
    done
    printf '  %s scriptlet(s) run, %s failed\n' "$ran" "$failed"
    [ "$failed" -eq 0 ] || printf '  failed:%s\n' "$failed_names" >&2
}

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
#   zlib -- EN PREMIER, et avant binutils. La bibliotheque bâtie sur l'hôte
#   n'expose aucun symbole versionne la ou celle de l'etage 2 en expose
#   seize ; `nm -D` le montre en une ligne, inflateReset2 contre
#   inflateReset2@@ZLIB_1.2.3.4. Tout ce que l'etage 1 a lie contre le zlib
#   DE L'HOTE garde la reference versionnee, et l'edition de liens casse des
#   qu'on batit contre la version nue :
#
#     ld: libcurl.so.4: undefined reference to `inflateReset2@ZLIB_1.2.3.4'
#
#   binutils meurt la, gcc derriere lui, et git se met a se plaindre -- ce
#   qui emporte toute recette dont prepare() clone quoi que ce soit. Un seul
#   paquet mal place, et la moitie de la liste tombe.
#   pacman -- juste apres zlib. Celui de l'etage 1 est lie au gpgme de
#   l'hote et ne demarre pas ici : « libgpgme.so.11: cannot open shared
#   object file », quand le chroot porte notre .so.45. makepkg l'appelle
#   apres avoir bati, si bien que la roue est faite et le paquet perdu --
#   quatre recettes ont fini ainsi, toutes avec un build reussi.
#
#   L'ORDRE DE CETTE LISTE EST UN ORDRE DE DEPENDANCES, pas une enumeration.
#   Un paquet qui en bâtit un autre vient avant lui :
#
#     python-fastjsonschema  -> poetry.core valide pyproject.toml avec lui
#     python-poetry-core     -> backend de python-pkgconfig
#     python-vcs-versioning  -> setuptools-scm l'IMPORTE en se bâtissant
#
#   Chacune de ces trois a ete vue a l'oeuvre : un consommateur place avant
#   son fournisseur echoue, puis passe au tour suivant. Ce qui marche par
#   accident de relance doit marcher du premier coup.
STAGE2_FIRST=(zlib pacman texinfo libxml2 binutils pkgconf wget libxslt
              python-packaging python-pyproject-hooks python-build
              python-installer python-setuptools python-wheel
              python-fastjsonschema python-poetry-core
              python-vcs-versioning python-setuptools-scm
              python-markupsafe python-jinja python-pkgconfig
              cython gyp python-psutil)

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
    python-markupsafe python-jinja python-pkgconfig cython
    python-poetry-core python-vcs-versioning python-fastjsonschema gyp
    python-psutil
    # clang has no stage-1 package AT ALL -- not a contaminated one, none. The
    # host has no llvm-gtest, so clang cannot even configure outside. It is
    # here so a rebuilt chroot takes it back from repo2, which rust will need.
    clang
    lld
    rust
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
# nss joins them, for the cheapest of the three reasons: its source is
#
#   hg+https://hg.mozilla.org/projects/nss#tag=NSS_..._RTM
#
# a MERCURIAL checkout, and the chroot has no hg -- it stopped on
# `hg: command not found`. Packaging Mercurial would work and is not needed: the
# host has it, and this mechanism exists precisely to let the host do the
# fetching. Considered and rejected: mercurial itself is cheap (a Python
# application), but it drags python-docutils in for its man pages and would sit
# in the chroot forever to serve one package's source URL.
STAGE2_HOST_EXTRACT=(libxml2 wget nss)

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
    # CLONE IF ABSENT. Stage 2 used to refuse:
    #
    #   no checkout for python-jinja
    #
    # It could only rebuild what stage 1 had cloned -- which is wrong for every
    # package stage 2 builds and stage 1 cannot. libxslt was the first (Ubuntu's
    # libxml2 is too old to configure it), and the Python set followed (their
    # package() reads the running python's paths, so the host bakes in
    # dist-packages). Those are named in CHROOT_STAGE2_PKGS precisely because
    # only this stage can produce them, and then this stage would not fetch them.
    #
    # Pinned to upstream.lock like stage 1's clone, so a package first built here
    # is as reproducible as one built there.
    # A PKGBUILD THIS REPOSITORY WRITES ITSELF. Every package above is Arch's,
    # fetched and then patched, and that is the right default: it keeps the
    # port a set of differences rather than a fork. It cannot cover a tool Arch
    # has no reason to package at all -- zipl exists only on this architecture,
    # so there is nothing upstream to clone and nothing to diff against.
    #
    # Such a PKGBUILD lives in pkgbuild/<name>/ and is copied, not cloned. It
    # is deliberately NOT a fallback for a failed clone: a network error would
    # then silently build something other than what the name says.
    if [ -f "$HERE/../pkgbuild/$name/PKGBUILD" ]; then
        echo "  local PKGBUILD for $name"
        rm -rf "$dir"; mkdir -p "$dir"
        cp -r "$HERE/../pkgbuild/$name/." "$dir/"
    elif [ ! -d "$dir/.git" ]; then
        # La même base que l étage 1, et surchargeable pour la même raison :
        # elle était écrite en dur ici, donc un miroir local branché sur
        # bootstrap-pacman.sh ne servait qu à moitié.
        local url="${PKG_GIT_BASE:-https://gitlab.archlinux.org/archlinux/packaging/packages}/$name.git"
        local sha=""
        [ -f "$HERE/upstream.lock" ] &&
            sha=$(awk -v n="$name" '$1 == n {print $2}' "$HERE/upstream.lock")
        echo "  cloning $name"
        rm -rf "$dir"
        GIT_TERMINAL_PROMPT=0 git clone -q --depth 1 "$url" "$dir" || {
            rm -rf "$dir"; echo "  clone failed: $url" >&2; return 1; }
        if [ -n "$sha" ]; then
            # SAY SO WHEN THE PIN DOES NOT HOLD.
            #
            # These two commands were chained with && to an echo: when the
            # fetch or the checkout failed, nothing printed and the package
            # was built from whatever HEAD the shallow clone landed on, while
            # upstream.lock named a commit. The lock was ignored without a
            # word, which is the one outcome it exists to prevent.
            if git -C "$dir" fetch -q --depth 1 origin "$sha" 2>/dev/null &&
               git -C "$dir" checkout -q --detach FETCH_HEAD 2>/dev/null; then
                echo "  pinned to ${sha:0:9} (upstream.lock)"
            else
                echo "  PIN FAILED for $name: upstream.lock says ${sha:0:9}," \
                     "building against HEAD instead" >&2
            fi
        else
            echo "  NOTE: $name is not in upstream.lock; built against HEAD" >&2
        fi
    fi

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
            ( cd "$dir" && EL_STAGE="$STAGE_N" bash "$PATCH_DIR/$name.sh" ) || {
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
    # --skippgpcheck alone, NOT with --skipchecksums: with both set, makepkg
    # takes its "Skipping all source file integrity checks" branch and no
    # source is verified at all. With only this one, check_checksums still
    # runs. The keys are what is missing here, not the sums.
    local mkflags="--nodeps --ignorearch --skippgpcheck"
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
        # Symlinks that point out of the chroot.
        #
        # nss failed with
        #
        #   /build/nss/PKGBUILD: line 55: ../certdata2pem.py:
        #     No such file or directory
        #
        # on a file that was plainly there. makepkg links a PKGBUILD's local
        # source files into srcdir, and having extracted on the HOST it wrote the
        # host's absolute path -- $WORK/pkg/nss/certdata2pem.py. Inside the
        # chroot that path does not exist; only /build does. "No such file or
        # directory" for an executable is usually its interpreter, which sent the
        # first guess to the shebang; here it was the script itself, reached
        # through a link to nowhere.
        #
        # Rewritten to the same file as the chroot sees it. Only links under
        # $WORK/pkg are touched -- a link to anywhere else was not made by this
        # mechanism and is not ours to redirect.
        local _l _t _n=0
        while IFS= read -r _l; do
            _t=$(readlink "$_l")
            case "$_t" in
                "$WORK/pkg"/*) ln -sfn "/build/${_t#"$WORK/pkg/"}" "$_l"; _n=$((_n + 1)) ;;
            esac
        done < <(find "$dir/src" -maxdepth 2 -type l 2>/dev/null)
        [ "$_n" -gt 0 ] && printf '  %s source link(s) repointed at /build\n' "$_n"
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
    # LE CACHE PORTE LE MEME NOM ET N EST PLUS LE MEME FICHIER. pacman garde
    # ses téléchargements sous nom-version-release, qui ne change pas quand un
    # paquet est REBATI : la copie en cache reste l ancienne, sa somme ne
    # correspond plus à celle de la base, et l installation suivante meurt sur
    #
    #   error: failed to commit transaction (invalid or corrupted package)
    #
    # loin d ici, dans la construction d une image. Celui qui remplace le
    # paquet est le seul à savoir qu il faut oublier l ancien.
    local _cache _p
    for _cache in "$WORK"/pacman-*.cache; do
        [ -d "$_cache" ] || continue
        for _p in "${produced[@]}"; do
            rm -f "$_cache/${_p##*/}" "$_cache/${_p##*/}.sig" 2>/dev/null || true
        done
    done
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
    # Install what this package produced, MINUS the alternatives. zlib-ng
    # produces zlib-ng-compat, and installing it fails:
    #
    #   :: zlib-ng-compat-2.3.3-1 and zlib-1:1.3.2-3 are in conflict
    #
    # The package is correct and belongs in repo2; it just cannot be installed
    # beside the zlib this chroot was built with. CHROOT_EXCLUDE already says so
    # for the populate step, and the same list applies here -- one statement of
    # which packages cannot coexist, used in both places.
    local keep=() f2 pn2
    for f2 in "${produced[@]}"; do
        pn2=$(bsdtar -xOf "$f2" .PKGINFO 2>/dev/null | sed -n 's/^pkgname = //p')
        if printf ' %s ' "${CHROOT_EXCLUDE[*]}" | grep -q " ${pn2:-_} "; then
            printf '  not installed here: %s (alternative to an installed package)\n' "$pn2"
            continue
        fi
        keep+=("$f2")
    done
    if [ "${#keep[@]}" -eq 0 ]; then
        printf '  nothing to install\n'
        ( cd "$dir" && rm -rf src pkg ) || true
        return 0
    fi
    sudo pacman --root "$ROOT" --config "$CONF2" --cachedir "$CACHE" \
        --noconfirm --nodeps --nodeps -U "${keep[@]}" > "$WORK/stage$STAGE_N-inst-$name.txt" 2>&1 || {
        tail -10 "$WORK/stage$STAGE_N-inst-$name.txt" >&2; return 1; }
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
        space_ok || { echo "== stage $STAGE_N: stopping, disk too low =="; break; }
        log "stage $STAGE_N: $p"
        # watched, not a plain call: see bootstrap-pacman.sh. A hundred and
        # thirty-three packages is far too many to sit in front of, and one
        # silent build would hold the whole run.
        if watched "$WORK/stage$STAGE_N-log-$p.txt" stage2_build "$p"; then
            echo "$p" >> "$STATE2"; ok=$((ok + 1)); echo "OK    $p"
        else
            rc=$?
            fail=$((fail + 1)); failed+=("$p")
            if [ "$rc" -eq 2 ]; then
                echo "STALL $p  (no output for ${EL_STALL_MIN:-45} min, killed)"
            else
                echo "FAIL  $p  (see $WORK/stage$STAGE_N-log-$p.txt)"
            fi
            tail -5 "$WORK/stage$STAGE_N-log-$p.txt" | sed 's/^/      /'
        fi
    done
    echo
    echo "== stage $STAGE_N: $ok rebuilt, $fail failed =="
    [ "$fail" -eq 0 ] || printf '  failed: %s\n' "${failed[*]}"
}

# RESOLVE, at the end of every pass.
#
# WHY IT IS HERE AND NOT IN A SCRIPT SOMEBODY RUNS. Stage 1 has this check in
# test-chroot.sh and stage 2 had none, so six declared dependencies sat absent
# from repo2 for weeks -- clang naming compiler-rt, cython naming numpy,
# linux-headers naming pahole. `pacman -S clang` failed on every target and
# nothing said so. It took populating a stage-3 chroot from repo2 alone to
# notice. A check that must be remembered is a check that reports late.
#
# --nodeps is what makes the hole possible: a package builds without its
# dependencies being installable, and the repository accepts it. Nothing else
# in this pipeline ever asks whether the result can be INSTALLED.
#
# -Syp prints and installs nothing. The probe root and its dbpath must exist
# first, or alpm reports it as a bad --root argument rather than a directory it
# declined to create; and -y is needed because a fresh dbpath has no sync
# database, without which every package reads as "target not found".
resolve_check() {
    local probe="$ROOT.resolve" conf="$WORK/pacman-resolve.conf" out="$WORK/stage$STAGE_N-resolve.txt"
    local pkgs=()
    local f
    for f in "$REPO2"/*.pkg.tar.zst; do
        [ -e "$f" ] || continue
        f="${f##*/}"
        # nom-version-release-arch.pkg.tar.zst : les quatre derniers champs
        # partent, le reste EST le nom -- qui peut lui-meme porter des tirets.
        pkgs+=("$(echo "${f%-*-*-*.pkg.tar.zst}")")
    done
    [ ${#pkgs[@]} -gt 0 ] || { echo "  RESOLVE: no packages to check"; return 0; }

    # LA BASE PEUT ANNONCER CE QUI N EXISTE PLUS.
    #
    # repo-add ajoute, il ne retire pas. Quand un crochet supprime un
    # sous-paquet d une recette -- git-zsh-completion, ostra-cg -- le fichier
    # disparaît et son entrée reste. RESOLVE ne le voyait pas : il bâtit sa
    # liste depuis les FICHIERS, donc il n interroge jamais le fantôme. Un
    # invité, lui, lit la base, et meurt sur
    #
    #   error: target not found: ostra-cg
    #
    # loin d ici. Un fantôme se répare en rebâtissant la base depuis les
    # fichiers réels, puis en la re-signant.
    # A CHECK THAT READS NOTHING MUST NOT REPORT ZERO.
    #
    # This loop read no entry at all for as long as it existed: a quoting
    # mistake handed bsdtar a literal pattern, 2>/dev/null swallowed its
    # complaint, and "0 ghosts" was indistinguishable from "0 entries read".
    # A database of hundreds of packages that yields nothing IS the failure,
    # not the all-clear.
    local ghosts=0 seen=0 fname
    while read -r fname; do
        [ -n "$fname" ] || continue
        seen=$((seen + 1))
        [ -e "$REPO2/$fname" ] || {
            printf "  GHOST %s announced by the database, absent on disk\n" "$fname"
            ghosts=$((ghosts + 1))
        }
    done < <(bsdtar xOzf "$REPO2/core.db.tar.gz" '*/desc' 2>/dev/null \
             | awk '/^%FILENAME%$/{getline; print}')
    [ "$seen" -gt 0 ] ||
        printf "  GHOST: the database yielded no entry -- the check did not run\n"
    [ "$ghosts" -eq 0 ] ||
        printf "  %s ghost(s): rm the database, re-run repo-add, then sign-repo.sh\n" "$ghosts"

    cat > "$conf" <<EOF
[options]
Architecture = s390x
SigLevel = Never
[core]
Server = file://$REPO2
EOF
    sudo rm -rf "$probe"; sudo mkdir -p "$probe/var/lib/pacman"
    log "RESOLVE: can everything in repo$STAGE_N be installed together?"
    if sudo pacman --root "$probe" --config "$conf" --cachedir "$CACHE" \
            --noconfirm -Syp "${pkgs[@]}" > "$out" 2>&1; then
        printf '  ok    %s packages resolve\n' "${#pkgs[@]}"
    else
        printf '  FAIL  unsatisfied, and each one fails on a target too:\n'
        grep -E "unable to satisfy|target not found" "$out" \
            | sed 's/.*dependency //; s/ required by/ <-/' | sort -u \
            | sed 's/^/        /'
        printf '        full output: %s\n' "$out"
    fi
    sudo rm -rf "$probe"
}

# UNE SIGNATURE NE SURVIT PAS A UN repo-add.
#
# `repo-add` réécrit core.db à chaque paquet ajouté ; la signature posée à côté
# reste celle de la base d'avant. pacman ne dit pas « signature périmée », il
# dit
#
#   error: core: signature from "..." is invalid
#
# et refuse le dépôt ENTIER -- ce qui, sur un invité qui vérifie, ressemble à
# une clé compromise plutôt qu'à une passe de construction. Signer est donc une
# opération à refaire, pas un état acquis.
#
# Re-signé seulement si le dépôt L ETAIT déjà : un dépôt sans signature n'en
# gagne pas une par surprise, et une passe ne réclame pas une clé à qui n'en a
# pas voulu.
resign_repo() {
    [ -f "$REPO2/core.db.tar.gz.sig" ] || return 0
    local here
    here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ ! -x "$here/sign-repo.sh" ]; then
        echo "  the repository is signed and sign-repo.sh is missing: its signature is now stale" >&2
        return 0
    fi
    log "Re-signing: repo-add rewrote the database"
    # THE FILTER DROPPED EXACTLY WHAT MATTERED.
    #
    # The output went through `sed -n 's/^  /    /p'`, which keeps only lines
    # already indented by two spaces -- sign-repo.sh's own progress. Its die
    # messages start at column one, so a failure printed nothing, and the
    # pipeline's status was tail's, which is always 0. A repository whose
    # database was rewritten and NOT re-signed looked exactly like one that
    # was, until a guest refused the whole repo for an invalid signature.
    local _out _rc
    _out="$(REPO2="$REPO2" bash "$here/sign-repo.sh" 2>&1)"; _rc=$?
    printf '%s\n' "$_out" | sed -n 's/^  /    /p' | tail -4
    if [ "$_rc" -ne 0 ]; then
        echo "  RE-SIGNING FAILED (exit $_rc); the database signature is stale:" >&2
        printf '%s\n' "$_out" | tail -6 | sed 's/^/    /' >&2
        return 1
    fi
}

main() {
    require_space
    [ -f "$REPO1/core.db.tar.gz" ] || die "no stage-1 repository at $REPO1"
    trap umount_chroot EXIT
    make_rootfs
    configure_chroot
    mount_chroot
    generate_ca_bundle
    run_scriptlets
    smoke_test || die "the chroot cannot build; stage 2 stops here"
    log "Chroot ready"
    if [ "$#" -eq 0 ]; then
        echo "  enter it with:"
        echo "    sudo chroot --userspec=$BUILD_UID:$BUILD_GID $ROOT /usr/bin/bash -l"
        echo "  or rebuild packages:"
        echo "    bash $0 texinfo perl m4 autoconf ..."
        echo "    bash $0 --all      # all ${#STAGE1_PACKAGES[@]}, in order"
        # THE MOUNTS MUST OUTLIVE THIS RETURN.
        #
        # Called with no argument -- the documented way to prepare the chroot
        # and look inside it -- this branch prints the command to enter it and
        # returns. The EXIT trap then unmounted proc, sys, dev, /build and
        # /repo2, so the command printed one line earlier landed in a chroot
        # with an EMPTY /build, and the first makepkg died on
        #
        #   /usr/bin/bash: line 1: cd: /build/<name>: No such file or directory
        #
        # the same sentence a missing host directory produces -- sending the
        # reader to look at $WORK/pkg, which is perfectly populated.
        #
        # Leaving them mounted is safe: make_rootfs starts by unmounting and
        # checks with findmnt, so the next pass takes them back cleanly.
        trap - EXIT
        echo "  the chroot stays mounted; the next pass remounts it cleanly"
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
    # Après la passe, pas avant : ce qui vient d'être bâti est ce qu'il faut
    # interroger, et un paquet ajouté peut fermer un trou comme en ouvrir un --
    # pahole a introduit ostra-cg, qui réclamait matplotlib.
    resolve_check
    resign_repo
}

main "$@"
