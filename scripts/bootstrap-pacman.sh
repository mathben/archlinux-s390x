#!/usr/bin/env bash
# Bootstrap the Arch packaging toolchain (pacman, makepkg, repo-add) on an
# s390x host, then build official Arch PKGBUILDs for s390x.
#
# WHY THIS IS THE KEYSTONE
#
# The README lists "pacman, bash and GNU coreutils are not yet ported" as three
# missing pieces. They are not three tasks -- pacman is the only one that
# matters, because pacman's source tree also ships makepkg and repo-add. Once
# those three run, every remaining package stops being hand-work and becomes
# `makepkg` on the upstream PKGBUILD.
#
# NO CROSS-COMPILATION IS NEEDED HERE. This runs on native s390x hardware, so
# the whole userspace builds at full speed with the host toolchain. That drops
# the z/VM round-trip the other scripts need.
set -euo pipefail

WORK="${WORK:-$HOME/work/arch-s390x}"
REPO="${REPO:-$WORK/repo/s390x}"
PACMAN_GIT="https://gitlab.archlinux.org/pacman/pacman.git"
PKG_GIT_BASE="https://gitlab.archlinux.org/archlinux/packaging/packages"

log() { printf '\n== %s ==\n' "$*"; }

install_host_deps() {
    log "Host build dependencies"
    # bsdtar and fakeroot are makepkg's own requirements, not the package's:
    # without them it fails deep inside extraction with a bare
    # "bsdtar: command not found".
    sudo apt-get -o DPkg::Lock::Timeout=600 install -y -qq \
        meson ninja-build pkg-config gettext \
        libarchive-dev libcurl4-openssl-dev libgpgme-dev libssl-dev \
        libarchive-tools fakeroot \
        build-essential autoconf automake libtool m4 patch texinfo bison flex \
        zstd xz-utils bzip2
}

build_pacman() {
    log "pacman + makepkg + repo-add"
    mkdir -p "$WORK"
    [ -d "$WORK/pacman" ] || git clone --depth 1 "$PACMAN_GIT" "$WORK/pacman"
    cd "$WORK/pacman"
    # /usr/local, never /usr: this host is Ubuntu and /usr belongs to dpkg.
    # makepkg resolves its own libraries from the configured prefix, so the
    # prefix has to be real -- running it from the build tree fails with
    # "/usr/share/makepkg/*.sh: No such file or directory".
    rm -rf build
    meson setup build --prefix=/usr/local --buildtype=release \
        -Ddoc=disabled -Ddoxygen=disabled -Di18n=false
    ninja -C build -j"$(nproc)"
    sudo ninja -C build install
}

configure_makepkg() {
    log "makepkg configuration"
    # CARCH is already detected as s390x by meson; CHOST must stay the
    # auto-detected triplet -- configure scripts are matched against it, and
    # inventing "s390x-pc-linux-gnu" breaks them.
    sudo sed -i "s|^#\?MAKEFLAGS=.*|MAKEFLAGS=\"-j$(nproc)\"|" /etc/makepkg.conf
    # pacman refuses to initialise alpm without its database directory. The
    # error is only a warning during packaging, but it hides real ones.
    sudo mkdir -p /var/lib/pacman
    grep -E '^(CARCH|CHOST|MAKEFLAGS)=' /etc/makepkg.conf
}

# build_package <name> -- fetch the official PKGBUILD and build it for s390x.
#
# --ignorearch: upstream PKGBUILDs carry arch=(x86_64) and nothing else.
# --skipchecksums: GitLab regenerates .patch URLs, so their checksums drift
#   from what the PKGBUILD recorded. Release tarballs still validate; only
#   the generated patches are skipped.
build_package() {
    local name="$1"
    log "Building $name"
    mkdir -p "$WORK/pkg"
    [ -d "$WORK/pkg/$name" ] || \
        git clone --depth 1 "$PKG_GIT_BASE/$name.git" "$WORK/pkg/$name"
    cd "$WORK/pkg/$name"
    makepkg --nodeps --ignorearch --skippgpcheck --skipchecksums -f
    mkdir -p "$REPO"
    cp -f ./*.pkg.tar.* "$REPO/"
    cd "$REPO"
    repo-add core.db.tar.gz ./*.pkg.tar.*
}

main() {
    install_host_deps
    build_pacman
    configure_makepkg
    for p in "$@"; do build_package "$p"; done
    log "Done"
    command -v pacman makepkg repo-add
}

# Only run when executed, never when sourced: build-stage1.sh reuses
# build_package() and must not re-run the whole bootstrap to get it.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
