#!/usr/bin/env bash
# libevent: no Doxygen API reference.
#
#   -- Could NOT find Doxygen (missing: DOXYGEN_EXECUTABLE)
#   CMake Error at cmake/UseDoxygen.cmake:108 (message):
#
# EVENT__DOXYGEN=ON makes it a hard requirement. doxygen is the most expensive of
# the documentation tools this port declined -- it wants clang, fmt, spdlog and
# llvm-libs, an entire compiler infrastructure to produce HTML.
set -euo pipefail
python3 - <<'ZZPY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()
old = "-D EVENT__DOXYGEN=ON"
assert s.count(old) == 1, "libevent: expected one EVENT__DOXYGEN, got %d" % s.count(old)
s = s.replace(old, "-D EVENT__DOXYGEN=OFF", 1)
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
ZZPY
grep -q "EVENT__DOXYGEN=OFF" PKGBUILD || { echo "libevent: doxygen not disabled" >&2; exit 1; }
echo "libevent: Doxygen reference disabled"
