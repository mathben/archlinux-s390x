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
    #   - libcap needs pam; openssl needs brotli; libarchive needs libxml2
    #   - pacman itself asks for systemd, pacman-mirrorlist and
    #     libmakepkg-dropins
    # Sixty-eight successful builds proved none of this. One chroot did.
    #
    # The chroot also named libselinux, and libselinux is NOT on this line,
    # because that reading of it was wrong. Arch has no libselinux package at
    # all -- the clone 404s. What the chroot saw was a HOST artefact: Ubuntu
    # carries libselinux1-dev, coreutils probes for selinux/selinux.h
    # unconditionally, and ours came out linked to a library the target will
    # never contain. The answer is --without-selinux per package, which is
    # what Arch's own build chroot gets for free by not having the header.
    pam brotli libxml2 systemd pacman-mirrorlist libmakepkg-dropins
    # The closure, named by pacman's own resolver rather than guessed.
    #
    # Everything above was added because a BUILD stopped. These were added
    # because scripts/test-chroot.sh ran `pacman -Syp` with --nodeps OFF --
    # the check the whole bootstrap skips -- and the resolver listed exactly
    # what the repository still owes. Nothing here is speculative.
    #
    # It is the MINIMAL closure, and two measurements shaped it. Dropping the
    # python-brotli sub-package took the list from 70 unresolved names to 47
    # and removed `python` outright, with libffi, mpdecimal and gdbm behind
    # it. Dropping systemd-ukify and systemd-tests removed five more python
    # packages, and ukify cannot run on s390x at all. Both are recorded in
    # TODO.md rather than left implicit.
    #
    # An audit of the remaining names against the ARTEFACTS found two that
    # were declared and never linked: guile by make, and libisl.so by gcc.
    # Both get their declaration removed, because it should describe the
    # binary we shipped.
    #
    # Building isl instead was the first plan, and it is recorded here because
    # the reason it failed is the kind that wastes an afternoon: the Arch
    # packaging repo for isl was last touched in 2017 and its only source URL
    # is isl.gforge.inria.fr, which died with INRIA's GForge. There is nothing
    # to build. That flipped the decision -- not a change of mind, new
    # evidence.
    #
    # These will pull their own dependencies. That is expected: the resolver
    # will name the next round as precisely as it named this one.
    audit ca-certificates cryptsetup dbus elfutils gettext gnutls hwdata
    icu jansson kbd kmod krb5 libcap-ng libgcrypt libidn2 libksba
    libmpc libnsl libseccomp libssh2 libtirpc libunistring libusb libxcrypt
    nettle npth openldap pambase pcre2 perl pinentry sqlite tpm2-tss
    # Closure, second round. The first thirty-five pulled these in, exactly as
    # the comment above predicted, and the resolver named them just as
    # precisely.
    #
    # THE MEASUREMENT THAT MATTERS HERE IS THE ONE THAT CHANGED ITS ANSWER.
    # Four of these were going to be avoided by dropping a sub-package --
    # sqlite-tcl, sqlite-analyzer, the openldap server, debuginfod -- on the
    # reasoning that had removed python-brotli earlier. Measured instead of
    # assumed, tcl, unixodbc and libmicrohttpd each cost ZERO new packages:
    # the closure had filled in around them. Building them is cheaper than
    # four hooks, and it does not leave sqlite shipping an sqltclsh that
    # cannot start.
    #
    # python still costs three (libffi, mpdecimal, gdbm) and is still avoided
    # -- but for the ABI reason, not the cost one: python-audit and
    # python-capng are cp313 wheels and Arch ships 3.14. Their hooks say so.
    #
    db5.3 gdbm e2fsprogs gnulib-l10n json-c keyutils p11-kit libsasl
    libsodium libtasn1 libverto lmdb popt lvm2 tcl unixodbc libmicrohttpd
    # ca-certificates-mozilla, which is the only thing here that is not a
    # library. It is the LIST OF ROOT CERTIFICATES -- ca-certificates itself
    # is only the trust machinery around it, so without this the target has a
    # trust store containing nothing, and every HTTPS verification fails.
    # curl declares ca-certificates, and pacman fetches through curl.
    #
    # It has no packaging repo of its own: the clone 404s, which
    # gitlab.archlinux.org reports by asking for a login -- the same
    # misleading shape that made libselinux look like a network problem. nss
    # produces it as a sub-package, so nss is what gets built, and nspr comes
    # with it.
    #
    # Measured before committing to it rather than estimated: nspr costs
    # nothing new, nss needs only nspr plus mercurial on the host, and
    # hg.mozilla.org answers from this build host (HTTP 302 in 0.3s -- worth
    # checking, since dev.gnupg.org does not answer at all and libassuan
    # needed a source change because of it).
    nspr nss
    # Closure, third round, and it is two packages. Both were pulled in by
    # what the second round added, and both cost nothing further: libffi by
    # libp11-kit, libevent by libverto.
    #
    # They are worth a line because of what they unblocked. p11-kit builds
    # into three packages, and libp11-kit's dependency on libffi was holding
    # up the whole chain ca-certificates -> ca-certificates-utils -> p11-kit
    # -> libp11-kit. The resolver reported it as "ca-certificates required by
    # curl" -- four links away from the missing name, and nothing in that
    # message points at libffi.
    libffi libevent
    # Closure, fourth round -- and it closed to NOTHING, which is the point
    # worth recording. It asked for libaio and thin-provisioning-tools, both
    # wanted by lvm2 alone. thin-provisioning-tools is Rust now, so that was a
    # language runtime arriving through a fourth-order dependency.
    #
    # Nothing in the repository wants `lvm2`. Checked across every .PKGINFO:
    # cryptsetup wants device-mapper, and device-mapper is the OTHER package
    # this same source produces. Dropping the lvm2 sub-package removed both
    # entries and the Rust question with them -- see patches/pkgbuild/lvm2.sh.
    #
    # 35 packages, then 19, then 2, then 0. The closure has to be recomputed
    # after each round rather than once: lvm2 DECLARED libaio all along, and
    # the third round could not see it because lvm2 had not been built yet.
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
