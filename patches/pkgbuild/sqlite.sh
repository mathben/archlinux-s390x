#!/usr/bin/env bash
# sqlite: the tcl extension installs where Ubuntu's tclConfig.sh says, not
# where Arch's does.
#
#   mv: cannot stat '<pkgdir>/usr/lib/tcl8.6/sqlite*': No such file or directory
#
# THE TRAP is that tcl was found. The log says so, plainly:
#
#   Checking for tclsh8.6.../usr/bin/tclsh8.6
#   Using tclConfig.sh: /usr/lib/s390x-linux-gnu/tclConfig.sh
#
# so "install tcl-dev" looks like it worked, and the failure looks like a
# separate problem. It is the same problem one layer down: tclConfig.sh
# carries TCL_PACKAGE_PATH, and Ubuntu's says share/tcltk while Arch's says
# lib. Measured in the pkgdir:
#
#   usr/share/tcltk/tcl8.6/sqlite3.53.4/libsqlite3.53.4.so
#
# and usr/lib/tcl8.6 does not exist at all. This is the multiarch libdir theme
# again -- a path the BUILD HOST decides -- but one layer out from the library
# directory itself, which is why --libdir does not reach it.
#
# The tree is relocated to Arch's path before package_sqlite() splits it out,
# so the upstream mv keeps working unchanged. Same shape as the lib64 merge in
# gcc.sh: move the tree, do not rewrite every path that names it.
set -euo pipefail
python3 - <<'PY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()
anchor = "  # split out tcl extension\n"
assert s.count(anchor) == 1, "sqlite: expected one tcl split block"
fix = """  # Ubuntu's tclConfig.sh puts the tcl package tree under share/tcltk;
  # Arch's puts it under lib. Move it before the split below reads it.
  if [ -d "$pkgdir"/usr/share/tcltk/tcl8.6 ]; then
    mkdir -p "$pkgdir"/usr/lib
    mv "$pkgdir"/usr/share/tcltk/tcl8.6 "$pkgdir"/usr/lib/tcl8.6
    rmdir --ignore-fail-on-non-empty "$pkgdir"/usr/share/tcltk
  fi
"""
s = s.replace(anchor, fix + anchor, 1)
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
PY
grep -q "tclConfig.sh puts the tcl package tree" PKGBUILD || {
    echo "sqlite: tcl relocation not inserted" >&2; exit 1; }
echo "sqlite: tcl extension relocated from share/tcltk to lib (host TCL_PACKAGE_PATH)"
