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

# --- and the docs split, which I left behind ----------------------------------
#
#   mv: cannot stat '<pkgdir>/usr/share/doc': No such file or directory
#
# Turning EVENT__DOXYGEN off above stopped the documentation being BUILT and left
# package() moving it into the libevent-doc split:
#
#   mv {"$pkgdir",doc}/usr/share/doc
#
# NINTH time in this port, and the second time I have made it myself rather than
# inherited it: fakeroot was the other. Removing a documentation build without
# removing its install is apparently the easiest mistake available here, so it is
# worth stating the rule plainly -- after disabling documentation anywhere,
# search package() for share/doc, man, and the split arrays before believing the
# hook is finished.
python3 - <<'ZZPY'
import io, re
lines = io.open("PKGBUILD", encoding="utf-8").read().split("\n")
hit = [i for i, l in enumerate(lines) if re.search(r"share/doc", l) and l.lstrip().startswith("mv ")]
assert len(hit) == 1, "libevent: expected one share/doc move, got %d" % len(hit)
i = hit[0]
ind = re.match(r"^[ \t]*", lines[i]).group(0)
lines[i] = ind + ': # doxygen is off above, so usr/share/doc is never created.'
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lines))
ZZPY
grep -qE "^[[:space:]]*mv .*share/doc" PKGBUILD && {
    echo "libevent: the docs move survived" >&2; exit 1; }
echo "libevent: docs split removed (nothing builds them now)"
