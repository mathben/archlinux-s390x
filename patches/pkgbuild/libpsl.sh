#!/usr/bin/env bash
# libpsl: no gtk-doc.
#
#   configure: error: ... documentation by adding '--disable-gtk-doc' to
#   './configure'.
#
# The error names its own fix, which is the whole of this hook. gtk-doc is a
# GNOME documentation toolchain; --enable-gtk-doc is in the PKGBUILD and the
# tool is not here.
set -euo pipefail
python3 - <<'ZZPY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()
old = "--enable-gtk-doc"
assert s.count(old) == 1, "libpsl: expected one --enable-gtk-doc, got %d" % s.count(old)
s = s.replace(old, "--disable-gtk-doc", 1)
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
ZZPY
grep -q -- "--disable-gtk-doc" PKGBUILD || { echo "libpsl: gtk-doc not disabled" >&2; exit 1; }
echo "libpsl: gtk-doc disabled"
