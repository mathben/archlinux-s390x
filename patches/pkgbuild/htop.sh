#!/usr/bin/env bash
# htop: no sensors, because this architecture exposes none.
#
# --enable-sensors makes htop read CPU temperatures through libsensors, and
# drags lm_sensors in as a build dependency:
#
#   configure: error: cannot find required header file sensors/sensors.h
#
# A guest on this architecture has no thermal hardware to read -- the values
# belong to the machine underneath, which does not publish them to a virtual
# CPU. Building lm_sensors would add a package whose readings would be empty.
#
# WHAT IS LOST: the temperature meters in htop's header. Everything else --
# processes, memory, load, the tree view -- is untouched.
#
# THE CONTINUATION TRAP. ./configure's options are joined by backslashes, so
# commenting a line out does not remove an option: it ends the continuation
# and turns the next option into a command.
#
#   /build/binutils/PKGBUILD: line 107: --enable-plugins: command not found
#
# binutils learned that here. The line is deleted whole, backslash included.
set -euo pipefail
python3 - <<'ZZPY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()

old = "      --enable-sensors \\\n"
assert s.count(old) == 1, "htop: la ligne --enable-sensors est introuvable"
s = s.replace(old, "", 1)

old = "makedepends=('git' 'lm_sensors')"
new = "makedepends=('git')"
assert s.count(old) == 1, "htop: makedepends inattendu"
s = s.replace(old, new, 1)

old = "optdepends=('lm_sensors: show cpu temperatures'\n"
if s.count(old) == 1:
    s = s.replace(old, "optdepends=(", 1)

io.open("PKGBUILD", "w", encoding="utf-8").write(s)
ZZPY
grep -q -- "--enable-sensors" PKGBUILD && { echo "htop: l option survit" >&2; exit 1; }
grep -q "lm_sensors" <<< "$(sed -n '/^makedepends=/p' PKGBUILD)" && {
    echo "htop: lm_sensors survit en makedepends" >&2; exit 1; }
bash -n PKGBUILD || { echo "htop: le PKGBUILD ne s analyse plus" >&2; exit 1; }
echo "htop: sensors retire, lm_sensors avec"
