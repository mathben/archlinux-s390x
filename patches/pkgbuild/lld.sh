#!/usr/bin/env bash
# lld: no Sphinx, and therefore no ld.lld.1 to install.
#
# THE DOCUMENTATION PATTERN, eighteenth appearance, and the first one caught by
# reading package() before the build rather than after it. -DLLVM_ENABLE_SPHINX=ON
# would drag in the whole sphinx tree for one man page; turning it off leaves
#
#   install -Dm644 -t "$pkgdir/usr/share/man/man1" ../docs/ld.lld.1
#
# pointing at a file Sphinx was the only thing that produced. install is not mv:
# it fails outright, so this would have been a failed package(), not a package
# quietly missing its manual.
#
# The cleanup two lines below it -- rm -r on html/{_sources,.buildinfo} -- has
# the same shape and is made tolerant instead of deleted: on a machine that does
# have Sphinx the directory is real and still has to go.
set -euo pipefail
python3 - <<"ZZPY"
import io
s = io.open("PKGBUILD", encoding="utf-8").read()

old = "-DLLVM_ENABLE_SPHINX=ON"
assert s.count(old) == 1, "lld: expected one LLVM_ENABLE_SPHINX, got %d" % s.count(old)
s = s.replace(old, "-DLLVM_ENABLE_SPHINX=OFF", 1)

lines = s.split("\n")
hit = [i for i, l in enumerate(lines) if "ld.lld.1" in l]
assert len(hit) == 1, "lld: expected one ld.lld.1 install, got %d" % len(hit)
del lines[hit[0]]

hit = [i for i, l in enumerate(lines) if "_sources" in l and l.lstrip().startswith("rm ")]
assert len(hit) == 1, "lld: expected one _sources removal, got %d" % len(hit)
lines[hit[0]] = lines[hit[0]].replace("rm -r ", "rm -rf ", 1)
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lines))
ZZPY
grep -q -- "-DLLVM_ENABLE_SPHINX=OFF" PKGBUILD || { echo "lld: sphinx not disabled" >&2; exit 1; }
grep -q "ld.lld.1" PKGBUILD && { echo "lld: still installing a man page nothing generates" >&2; exit 1; }
grep -qE "^[[:space:]]*rm -rf .*_sources" PKGBUILD || { echo "lld: the cleanup is not tolerant" >&2; exit 1; }
echo "lld: Sphinx disabled, ld.lld.1 install removed, cleanup made tolerant"
