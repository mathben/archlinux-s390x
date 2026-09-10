#!/usr/bin/env bash
# python-psutil: the build stays, the test suite goes.
#
# THE BUILD IS FINE. It produces psutil-7.2.2-cp36-abi3-linux_s390x.whl and
# stops there; nothing about this package is unported. What fails is check():
#
#   test-env/bin/python: No module named pytest
#
# MEASURED, because the alternative was to supply pytest and that is where it
# leads: checkdepends are python-pytest, net-tools and procps-ng, none of which
# this port builds. python-pytest wants python-iniconfig, python-pluggy and
# python-pygments -- and python-pygments makedepends on python-sphinx,
# python-hatchling and python-wcag-contrast-ratio. That is the same fifteen-odd
# package Sphinx tree the llvm and clang hooks already refused, reached by a
# different road. iniconfig and pluggy also have python-pytest in THEIR
# checkdepends, so the chain is circular on top of being large.
#
# AND NOTHING HERE NEEDS THE VERDICT. llvm names python-psutil among its
# makedepends, and llvm ran its own suite at stage 2 without it: 68603 tests
# passed, 178 expectedly failed, in 303 seconds. RESOLVE passes with psutil
# absent from the repository entirely. The tests would tell us about psutil on
# s390x, which is worth knowing -- but not at the price of the tree that
# reports it.
#
# Deleted rather than emptied: an empty check() reads as a suite that passes.
set -euo pipefail
python3 - <<'ZZPY'
import io, re
s = io.open("PKGBUILD", encoding="utf-8").read()
lines = s.split("\n")
start = [i for i, l in enumerate(lines) if l.startswith("check()")]
assert len(start) == 1, "python-psutil: expected one check(), got %d" % len(start)
i = start[0]
end = next(j for j in range(i, len(lines)) if lines[j] == "}")
del lines[i:end + 2 if end + 1 < len(lines) and lines[end + 1] == "" else end + 1]
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lines))
ZZPY
grep -q "^check()" PKGBUILD && { echo "python-psutil: check() is still there" >&2; exit 1; }
grep -q "^package()" PKGBUILD || { echo "python-psutil: package() went missing -- deleted too much" >&2; exit 1; }
grep -q "^build()" PKGBUILD || { echo "python-psutil: build() went missing -- deleted too much" >&2; exit 1; }
echo "python-psutil: check() removed, build and package intact"
