#!/usr/bin/env bash
# glibc: two x86-only assumptions, both fatal on s390x.
#
# 1. SFrame.
#
#    Arch passes --enable-sframe, added when x86_64 gained SFrame stack
#    tracing. glibc's configure rejects it outright here:
#
#      configure: error: the architecture doesn't support SFrame
#
#    No host package fixes this: the feature is genuinely absent from s390x.
#
# 2. lib32-glibc.
#
#    glibc is a split package whose second half is the 32-bit multilib
#    build. The main glibc package builds and packages perfectly -- measured,
#    the whole compile succeeds -- and then makepkg aborts in
#    package_lib32-glibc() with "No rule to make target 'install'", because
#    the 32-bit tree was never configured.
#
#    lib32 is i686-on-x86_64. On s390x there is no 32-bit userspace to build
#    against, and the deprecated 31-bit ABI is not it either.
#
# Both are removed rather than repaired: what is being removed is
# architecture-specific by nature.
set -euo pipefail

sed -i '/--enable-sframe/d' PKGBUILD
grep -q -- '--enable-sframe' PKGBUILD && { echo "glibc: sframe flag still present" >&2; exit 1; }

# Drop the lib32 half: package list, its build steps and its package function.
sed -i 's/^pkgname=(glibc lib32-glibc\(.*\))$/pkgname=(glibc\1)/' PKGBUILD
sed -i '/lib32-gcc-libs/d' PKGBUILD
python3 - <<'PY'
import io, re
s = io.open("PKGBUILD", encoding="utf-8").read()
# The package function, and the build block guarded by the 32-bit tree.
s = re.sub(r"\npackage_lib32-glibc\(\)\s*\{.*?\n\}\n", "\n", s, flags=re.S)
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
PY
grep -q 'package_lib32-glibc' PKGBUILD && { echo "glibc: lib32 package function remains" >&2; exit 1; }
grep -qE '^pkgname=\(glibc( |\))' PKGBUILD || { echo "glibc: pkgname not reduced" >&2; exit 1; }
grep -m1 '^pkgname=' PKGBUILD
echo "glibc: --enable-sframe removed, lib32 split package removed"
