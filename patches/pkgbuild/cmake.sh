#!/usr/bin/env bash
# cmake: --qt-gui, on a machine with no display and no Qt.
#
#   CMake Error at Source/QtDialog/CMakeLists.txt:33 (message):
#   Error when bootstrapping CMake:
#
# cmake-gui is a Qt application. Arch lists qt6-base in makedepends and builds
# it; this port has no Qt and will not grow one to give a bootstrap a dialog
# box. Same reasoning as pinentry's Qt front end, and the cost is the same
# thing: a graphical program nothing here can display.
#
# WHY cmake IS IN STAGE 1 AT ALL, since it is worth being clear that this is
# not scope creep: four PKGBUILDs call cmake directly, and stage 2 rebuilds
# every package inside a chroot that has to contain the build systems. cmake
# is a tool the REBUILD needs, not a dependency of anything in the repository
# -- which is why the dependency resolver never asked for it.
#
# --sphinx-man and --sphinx-html stay: sphinx-build is installed, and the man
# pages are worth having.
#
# The makedepends entry goes with the flag. Nothing checks it under --nodeps,
# but a package declaring a build dependency it does not use is the same
# untruth as gcc-libs declaring libhwasan -- and leaving it would tell the
# next reader that Qt was needed here.
set -euo pipefail
python3 - <<'ZZPY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()

old = "    --qt-gui \\\n"
assert s.count(old) == 1, "cmake: expected exactly one --qt-gui"
s = s.replace(old, "", 1)

old = "             qt6-base)"
assert s.count(old) == 1, "cmake: makedepends tail not in the expected form"
s = s.replace(old, "             )", 1)

io.open("PKGBUILD", "w", encoding="utf-8").write(s)
ZZPY
grep -q -- '--qt-gui' PKGBUILD && { echo "cmake: --qt-gui survived" >&2; exit 1; }
sed -n '/^makedepends=(/,/)/p' PKGBUILD | grep -q 'qt6-base' && {
    echo "cmake: qt6-base still in makedepends" >&2; exit 1; }
grep -q -- '--sphinx-man' PKGBUILD || {
    echo "cmake: man pages lost with the GUI" >&2; exit 1; }
echo "cmake: --qt-gui dropped (no Qt, no display)"
