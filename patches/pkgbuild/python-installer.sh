#!/usr/bin/env bash
# One of the six packages in the Python packaging cycle. The reasoning, and the
# edit, are shared -- see lib-python-bootstrap.sh.
set -euo pipefail
source "$(dirname "$0")/lib-python-bootstrap.sh"

# THE WINDOWS ENTRYPOINTS ARE REMOVED BY A GLOB THAT ASSUMES ARCH'S LAYOUT.
#
#   rm "$pkgdir"/usr/lib/python*/site-packages/installer/_scripts/*.exe
#
# Stage 1 builds with the host interpreter, which installs into the
# distribution's own directory -- dist-packages, not site-packages. The glob
# then matches nothing, is passed through literally, and rm stops package()
# on a path containing an unexpanded asterisk. The files are present; only the
# pattern is wrong.
#
# find matches either layout and needs no interpreter to resolve the version
# component. It is also quiet when the wheel ships none, which a future
# release may well do.
python3 - <<'ZZPY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()
old = 'rm "$pkgdir"/usr/lib/python*/site-packages/installer/_scripts/*.exe'
assert s.count(old) == 1, "installer: la ligne rm des .exe est introuvable"
new = ('find "$pkgdir" -path "*/installer/_scripts/*" -name "*.exe" -delete')
s = s.replace(old, new, 1)
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
ZZPY
grep -q 'site-packages/installer/_scripts' PKGBUILD && {
    echo "python-installer: le glob survit" >&2; exit 1; }
grep -q '_scripts/\*" -name "\*.exe" -delete' PKGBUILD || {
    echo "python-installer: le find n a pas ete pose" >&2; exit 1; }
echo "python-installer: .exe retires par find, les deux dispositions"
