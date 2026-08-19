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
WORK="${WORK:-$HOME/work/arch-s390x}"
REPO1="${REPO1:-$WORK/repo/s390x}"
REPO2="${REPO2:-$WORK/repo2/s390x}"
ROOT="${ROOT:-$WORK/rootfs-stage2}"
CONF="$WORK/pacman-stage2.conf"
CACHE="$WORK/pacman-stage2.cache"
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
)

log()  { printf '\n== %s ==\n' "$*"; }
die()  { printf 'stage2: %s\n' "$*" >&2; exit 1; }

require_space() {
    local free_mb
    free_mb=$(df -Pm "$WORK" | awk 'NR==2 {print $4}')
    [ "${free_mb:-0}" -ge 8192 ] || die "only ${free_mb} MiB free under $WORK; need 8192"
}

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
    sudo pacman --root "$ROOT" --config "$CONF" --cachedir "$CACHE" \
        --noconfirm -Sy "${CHROOT_PKGS[@]}" > "$WORK/stage2-install.txt" 2>&1 \
        || { tail -20 "$WORK/stage2-install.txt" >&2; die "populate failed"; }
    printf '  %s packages installed\n' "$(sudo ls "$ROOT/var/lib/pacman/local" | wc -l)"
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
    sudo grep -E '^(CARCH|CHOST|MAKEFLAGS|OPTIONS)=' "$ROOT/etc/makepkg.conf" | sed 's/^/  /'

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
        HOME=/build PATH=/usr/bin \
        LC_ALL=C.UTF-8 \
        /usr/bin/bash -lc "$*"
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

main() {
    require_space
    [ -f "$REPO1/core.db.tar.gz" ] || die "no stage-1 repository at $REPO1"
    trap umount_chroot EXIT
    make_rootfs
    configure_chroot
    mount_chroot
    smoke_test || die "the chroot cannot build; stage 2 stops here"
    log "Chroot ready"
    echo "  enter it with:"
    echo "    sudo chroot --userspec=$BUILD_UID:$BUILD_GID $ROOT /usr/bin/bash -l"
}

main "$@"
