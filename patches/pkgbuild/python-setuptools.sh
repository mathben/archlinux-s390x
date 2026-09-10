#!/usr/bin/env bash
# One of the six packages in the Python packaging cycle. The reasoning, and the
# edit, are shared -- see lib-python-bootstrap.sh.
#
# EXCEPT THAT SETUPTOOLS NEVER TAKES THE NORMAL PATH. The shared edit makes the
# choice conditional -- bootstrap unless `build` and `installer` import -- and
# that condition is right for the other five. It is wrong here, and stage 3 is
# what showed it: once those two were declared in CHROOT_PKGS the condition
# became true, the normal path was taken, and the build stopped on
#
#   BackendUnavailable: Cannot import 'setuptools.build_meta'
#
# with setuptools installed and importable everywhere else in the chroot. The
# reason is the working directory: `python -m build` runs inside the unpacked
# setuptools source, whose own `setuptools/` directory comes first on sys.path
# and shadows the installed package -- a source tree that cannot serve as its
# own build backend. Every OTHER package in the cycle is built from a source
# tree that shadows nothing it needs.
#
# So the condition is replaced by a constant here. Arch's vendored builder
# needs none of the six and does not care what the working directory holds.
set -euo pipefail
source "$(dirname "$0")/lib-python-bootstrap.sh"

python3 - <<'ZZPY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()

old = ("_bootstrap=1\n"
       "python -c 'import build, installer' >/dev/null 2>&1 && _bootstrap=0")
assert s.count(old) == 1, "setuptools: bloc conditionnel introuvable"
s = s.replace(old, "_bootstrap=1", 1)

io.open("PKGBUILD", "w", encoding="utf-8").write(s)
ZZPY
grep -q "import build, installer" PKGBUILD && {
    echo "python-setuptools: la condition survit" >&2; exit 1; }
grep -qE "^_bootstrap=1$" PKGBUILD || {
    echo "python-setuptools: _bootstrap n est pas force" >&2; exit 1; }
echo "python-setuptools: _bootstrap=1 sans condition"
