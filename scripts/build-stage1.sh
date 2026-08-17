#!/usr/bin/env bash
# Stage 1 of the port: build a self-hosting Arch `core` for s390x.
#
# THE THREE-STAGE DISCIPLINE, AND WHY IT IS NOT OPTIONAL
#
# Stage 1 builds with the HOST toolchain (Ubuntu gcc/glibc). Every package it
# produces is therefore linked against the host's glibc, not Arch's. That is
# acceptable -- and unavoidable, since Arch's glibc needs an Arch gcc which
# needs an Arch glibc -- but it is not a port yet.
#
# Stage 2 chroots into the stage-1 result and rebuilds everything with the
# stage-1 toolchain. Stage 3 repeats it, and a port is self-hosting once
# stage 3 reproduces stage 2. Skipping this leaves host artefacts baked into
# packages that will fail months later, far from their cause.
#
# This script is stage 1 only.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/bootstrap-pacman.sh"

WORK="${WORK:-$HOME/work/arch-s390x}"
REPO="${REPO:-$WORK/repo/s390x}"
STATE="$WORK/stage1.state"

# Build order. It follows link-time dependencies, not pacman metadata:
# --nodeps means pacman never checks, so anything a compiler actually needs
# must already exist. Within a group the order is free.
STAGE1_PACKAGES=(
    # Foundation: headers, then the C library, then the compiler chain.
    linux-api-headers glibc binutils gcc
    # Compression and crypto, needed by libarchive and curl further down.
    zlib bzip2 xz zstd lz4 openssl
    # Terminal handling: bash links against readline, readline against ncurses.
    ncurses readline
    # The shell, and the coreutils prerequisites Arch declares.
    attr acl gmp mpfr libcap bash coreutils
    # Text and file tools the build systems themselves call.
    sed grep gawk findutils diffutils file which patch
    # Archivers, then the library pacman reads packages with.
    tar gzip expat libarchive
    # Build systems.
    m4 autoconf automake libtool make pkgconf
    # pacman's network and signature stack.
    libnghttp2 libpsl curl libgpg-error libassuan gnupg gpgme
    # System skeleton: without these a rootfs has no /etc/passwd, no zones,
    # no /etc/services -- and nothing boots to a usable shell.
    filesystem iana-etc tzdata licenses shadow util-linux
    # Named by the chroot test, not guessed. Installing the repo into a
    # rootfs and entering it turned "does it work?" into a precise list:
    #   - coreutils links against libselinux, and would not start without it
    #   - libcap needs pam; openssl needs brotli; libarchive needs libxml2
    #   - pacman itself asks for systemd, pacman-mirrorlist and
    #     libmakepkg-dropins
    # Sixty-eight successful builds proved none of this. One chroot did.
    libselinux pam brotli libxml2 systemd pacman-mirrorlist libmakepkg-dropins
    # And finally the package manager itself, built as an Arch package.
    pacman
)

built() { grep -qxF "$1" "$STATE" 2>/dev/null; }
mark()  { echo "$1" >> "$STATE"; }

main() {
    mkdir -p "$WORK/pkg" "$REPO"
    touch "$STATE"
    # The stand-ins are read from /usr/local/bin, so a stage-1 run that never
    # reinstalls them silently builds with whatever was deployed weeks ago.
    # Cheap, idempotent, and it makes this repository the source of truth.
    install_host_shims
    local ok=0 fail=0 failed=()
    for p in "${STAGE1_PACKAGES[@]}"; do
        if built "$p"; then
            echo "== $p already built, skipping =="
            continue
        fi
        # A failure must not stop the run: one missing package should not hide
        # the state of the forty that follow. They are collected and reported.
        if build_package "$p" > "$WORK/log-$p.txt" 2>&1; then
            mark "$p"; ok=$((ok + 1))
            echo "OK    $p"
        else
            fail=$((fail + 1)); failed+=("$p")
            echo "FAIL  $p  (see $WORK/log-$p.txt)"
        fi
    done
    echo
    echo "== stage 1: $ok built, $fail failed =="
    [ "$fail" -eq 0 ] || printf '  failed: %s\n' "${failed[*]}"
}

main "$@"
