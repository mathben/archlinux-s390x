#!/usr/bin/env bash
# libtool: drop the 32-bit multilib split package.
#
# Arch builds libtool as (libtool lib32-libltdl). The build() step that
# compiles the 32-bit half is already guarded by [[ $CARCH = x86_64 ]] and
# never runs here -- but prepare() copies the source tree to src/libtool32
# UNCONDITIONALLY, and package_lib32-libltdl() then packages a tree that was
# never built:
#
#   cp: cannot create regular file '.../src/libtool32/libtool/.git...'
#
# lib32 is i686-on-x86_64 multilib. It has no meaning on s390x, where no
# 32-bit userspace is shipped and lib32-glibc does not exist. Removed rather
# than repaired: the artefact itself is architecture-specific.
set -euo pipefail
sed -i 's/^pkgname=(libtool lib32-libltdl)$/pkgname=(libtool)/' PKGBUILD
sed -i '/lib32-gcc-libs/d; /lib32-glibc/d; /libtool32/d' PKGBUILD
python3 - <<'PY'
import io, re
s = io.open("PKGBUILD", encoding="utf-8").read()
s = re.sub(r"\npackage_lib32-libltdl\(\)\s*\{.*?\n\}\n", "\n", s, flags=re.S)
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
PY
# Verify what actually matters. "lib32" also appears in a harmless
# lt_cv_sys_lib_dlsearch_path_spec string and in the CARCH-guarded block;
# grepping for the bare word declared a false failure.
grep -q '^pkgname=(libtool)$' PKGBUILD || { echo "libtool: pkgname not reduced" >&2; exit 1; }
grep -q 'package_lib32-libltdl' PKGBUILD && { echo "libtool: lib32 package function remains" >&2; exit 1; }
grep -q 'libtool32' PKGBUILD && { echo "libtool: libtool32 tree still referenced" >&2; exit 1; }
echo "libtool: lib32 split package removed (x86-only multilib)"
