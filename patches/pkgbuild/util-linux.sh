#!/usr/bin/env bash
# util-linux: s390x installs to lib64, Arch expects lib.
#
#   rm: cannot remove '.../pkg/util-linux/usr/lib/lib*.la': No such file
#
# The same divergence already handled in gcc.sh: 64-bit Z installs libraries
# into usr/lib64, while every Arch PKGBUILD names usr/lib. Here it shows up
# as a glob that matches nothing, which `rm` reports as a missing file rather
# than an empty expansion -- so the error names a path that was never going
# to exist.
#
# Merged before package() touches anything, so the upstream paths keep
# working unchanged.
set -euo pipefail
python3 - <<'PY'
import io, re
s = io.open("PKGBUILD", encoding="utf-8").read()
merge = """  # s390x installs 64-bit libraries to lib64; Arch expects lib.
  if [ -d "$pkgdir/usr/lib64" ]; then
    mkdir -p "$pkgdir/usr/lib"
    cp -a "$pkgdir/usr/lib64/." "$pkgdir/usr/lib/"
    rm -rf "$pkgdir/usr/lib64"
  fi
"""
m = re.search(r"\npackage_util-linux\(\) \{\n", s)
if not m:
    m = re.search(r"\npackage\(\) \{\n", s)
assert m, "package function not found"
s = s[:m.end()] + merge + s[m.end():]
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
PY
grep -q 'installs 64-bit libraries to lib64' PKGBUILD || {
    echo "util-linux: lib64 merge not inserted" >&2; exit 1; }
echo "util-linux: lib64 merged into lib before packaging"
