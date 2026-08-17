#!/usr/bin/env bash
# sed: --without-selinux. Same host artefact as coreutils.
#
#   $ readelf -d repo/s390x/.../usr/bin/sed | grep NEEDED
#     (NEEDED) Shared library: [libselinux.so.1]
#
# sed matters for the same reason find does: every PKGBUILD hook in this
# repository is a sed, and stage 2 runs them inside the stage-1 rootfs.
#
# Arch's sed declares depends=(acl glibc). The full account of why the host
# supplies a header Arch's build chroot does not is in
# patches/pkgbuild/coreutils.sh.
#
# One ./configure in this PKGBUILD (verified), so the anchor is unambiguous.
set -euo pipefail
grep -c -- '^  \./configure --prefix=/usr$' PKGBUILD | grep -qx 1 || {
    echo "sed: expected exactly one bare ./configure --prefix=/usr" >&2; exit 1; }
sed -i 's|^\(\s*\)\(\./configure --prefix=/usr\)$|\1\2 --without-selinux|' PKGBUILD
grep -c -- '--without-selinux' PKGBUILD | grep -qx 1 || {
    echo "sed: --without-selinux not inserted exactly once" >&2; exit 1; }
echo "sed: --without-selinux (Arch has no libselinux; the host does)"
