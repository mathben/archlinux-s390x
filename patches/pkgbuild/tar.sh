#!/usr/bin/env bash
# tar: --without-selinux. Same host artefact as coreutils.
#
#   $ readelf -d repo/s390x/.../usr/bin/tar | grep NEEDED
#     (NEEDED) Shared library: [libselinux.so.1]
#
# This is the one with the sharpest consequence. makepkg extracts every
# source with tar, so in stage 2 -- which runs makepkg inside the stage-1
# rootfs -- a tar that will not load stops the entire stage before its first
# package. Not cosmetic, and not something a later fix can route around.
#
# Arch's tar declares depends=(acl glibc). The full account of why the host
# supplies a header Arch's build chroot does not is in
# patches/pkgbuild/coreutils.sh.
#
# One ./configure in this PKGBUILD (verified), and it carries its own
# --sbindir/--libexecdir, so the anchor is the whole line rather than the
# bare form the other three match.
set -euo pipefail
grep -c -- '^  \./configure --prefix=/usr --sbindir=/usr/bin --libexecdir=/usr/lib/tar$' PKGBUILD | grep -qx 1 || {
    echo "tar: expected exactly one ./configure line" >&2; exit 1; }
sed -i 's|^\(\s*\)\(\./configure --prefix=/usr --sbindir=/usr/bin --libexecdir=/usr/lib/tar\)$|\1\2 --without-selinux|' PKGBUILD
grep -c -- '--without-selinux' PKGBUILD | grep -qx 1 || {
    echo "tar: --without-selinux not inserted exactly once" >&2; exit 1; }
echo "tar: --without-selinux (Arch has no libselinux; the host does)"
