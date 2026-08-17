#!/usr/bin/env bash
# findutils: --without-selinux. Same host artefact as coreutils.
#
# THE TRAP: fixing coreutils alone looks like the job is done. It is not.
#
#   $ readelf -d repo/s390x/.../usr/bin/find | grep NEEDED
#     (NEEDED) Shared library: [libselinux.so.1]
#
# and stage 2 runs makepkg INSIDE the stage-1 rootfs, where makepkg calls
# find. A find that will not load is a hard stop, not a cosmetic one.
#
# Arch's findutils declares depends=(glibc) and nothing else, because Arch's
# build chroot has no selinux/selinux.h for gnulib to probe. Ubuntu 25.10
# does, so ours linked it. patches/pkgbuild/coreutils.sh carries the full
# account, including why removing the header from the host is not available.
#
# One ./configure in this PKGBUILD (verified), so the anchor is unambiguous.
set -euo pipefail
grep -c -- '^  \./configure --prefix=/usr$' PKGBUILD | grep -qx 1 || {
    echo "findutils: expected exactly one bare ./configure --prefix=/usr" >&2; exit 1; }
sed -i 's|^\(\s*\)\(\./configure --prefix=/usr\)$|\1\2 --without-selinux|' PKGBUILD
grep -c -- '--without-selinux' PKGBUILD | grep -qx 1 || {
    echo "findutils: --without-selinux not inserted exactly once" >&2; exit 1; }
echo "findutils: --without-selinux (Arch has no libselinux; the host does)"
