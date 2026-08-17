#!/usr/bin/env bash
# coreutils: --without-selinux. The host has libselinux; Arch does not.
#
# THE TRAP: the chroot test reported "coreutils links against libselinux",
# and the obvious reading -- build libselinux next -- is wrong twice over.
#
#   $ readelf -d repo/s390x/.../usr/bin/ls | grep NEEDED
#     (NEEDED) Shared library: [libselinux.so.1]
#
# There is no libselinux package in Arch. The clone of it 404s, and
# gitlab.archlinux.org answers a 404 by asking for a login, which is why the
# driver log said "could not read Username" rather than "no such project".
# Arch's own coreutils declares depends=(acl attr glibc gmp libcap openssl)
# -- no selinux, because Arch's build chroot has no libselinux to find.
#
# Ours found one. Ubuntu 25.10 carries libselinux1-dev (it arrives with
# libmount-dev / libgio-2.0-dev), coreutils' configure probes for
# selinux/selinux.h unconditionally, and thirteen binaries -- ls, cp, mv,
# install, id, stat, mkdir, mknod, mkfifo, dir, vdir, chcon, runcon -- came
# out linked to a library the target rootfs will never contain.
#
# Uninstalling the header on the host is not the way out: apt takes
# libmount-dev, libglib2.0-dev, libcryptsetup-dev and libdevmapper-dev with
# it, which is what systemd and util-linux still need.
#
# So this is not disabling a feature. It is removing a HOST artefact that
# stage 1 exists to keep out, and the result matches Arch's binary exactly:
# Arch's coreutils ships neither chcon nor runcon, for this very reason.
# Losing them converges with Arch, it does not diverge from it.
#
# The same probe catches findutils, sed and tar -- each has its own hook --
# and glibc's makedb, which deliberately does NOT. Nothing in the bootstrap
# runs makedb, and rebuilding glibc for it would relink the foundation under
# all sixty-nine other packages. Stage 2 rebuilds glibc in a chroot that has
# no libselinux, where the problem cannot recur.
#
# Only one ./configure in this PKGBUILD (verified), so the anchor is safe.
set -euo pipefail
grep -c -- '--with-openssl' PKGBUILD | grep -qx 1 || {
    echo "coreutils: expected exactly one --with-openssl anchor" >&2; exit 1; }
sed -i 's|^\(\s*\)--with-openssl$|\1--with-openssl \\\n\1--without-selinux|' PKGBUILD
grep -q -- '--without-selinux' PKGBUILD || {
    echo "coreutils: --without-selinux not inserted" >&2; exit 1; }
echo "coreutils: --without-selinux (Arch has no libselinux; the host does)"
