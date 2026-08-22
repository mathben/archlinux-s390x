#!/usr/bin/env bash
# libuv: no man page.
#
#   Makefile:14: *** The 'sphinx-build' command was not found.
#
# TWO PLACES: `make man -C docs` builds it and package() installs
# docs/build/man/libuv.1. Removing only the build gives
#
#   install: cannot stat 'docs/build/man/libuv.1'
#
# which is the same shape as libxml2's docs split and pam's PDFs -- a failure on
# a path, at the end of package(), after a compile that worked.
set -euo pipefail
python3 - <<'ZZPY'
import io, re
lines = io.open("PKGBUILD", encoding="utf-8").read().split("\n")
mk = [i for i, l in enumerate(lines) if re.search(r"make man -C docs", l)]
assert len(mk) == 1, "libuv: expected one `make man -C docs`, got %d" % len(mk)
inst = [i for i, l in enumerate(lines) if "docs/build/man/libuv.1" in l]
assert len(inst) == 1, "libuv: expected one man install, got %d" % len(inst)
i = inst[0]
# The install spans two lines: the source and the destination.
j = i
while lines[j].rstrip().endswith("\\"):
    j += 1
del lines[i:j + 1]
del lines[mk[0]]
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lines))
ZZPY
grep -qE "make man -C docs|libuv\.1" PKGBUILD && {
    echo "libuv: a man page reference survived" >&2; exit 1; }
echo "libuv: man page dropped (no sphinx)"
