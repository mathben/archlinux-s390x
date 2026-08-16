#!/usr/bin/env bash
# glibc: SFrame does not exist on s390x.
#
# Arch's PKGBUILD passes --enable-sframe, added when x86_64 gained SFrame
# stack tracing. glibc's own configure rejects it outright on this
# architecture:
#
#   configure: error: the architecture doesn't support SFrame
#
# This is not a build-environment problem and no host package fixes it: the
# feature is genuinely absent from s390x. Dropping the flag is what a port
# does -- and it must be dropped surgically, leaving every other configure
# option untouched, so that a future Arch change to this PKGBUILD is not
# silently discarded.
set -euo pipefail
sed -i '/--enable-sframe/d' PKGBUILD
grep -q -- '--enable-sframe' PKGBUILD && { echo "glibc: sframe flag still present" >&2; exit 1; }
echo "glibc: --enable-sframe removed (unsupported on s390x)"
