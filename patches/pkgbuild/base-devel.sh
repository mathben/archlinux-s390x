#!/usr/bin/env bash
# base-devel: drop archlinux-keyring.
#
# base-devel compiles nothing -- it is a depends array and a name every Arch
# guide uses, ERPLibre install_arch_linux.sh included. Two of its entries do
# not exist here, and they are not the same kind of absence.
#
# debugedit IS BUILT, because it is a tool: makepkg calls it to produce debug
# packages, and a build machine that cannot is a build machine with a hole. It
# is in the package list, next to this.
#
# archlinux-keyring IS REMOVED, because it is trust and there is none to carry.
# It ships the PGP keys of Arch's developers, and NOT ONE package on this
# system was signed by them: every one was built here, from patched PKGBUILDs,
# with signature checking off. Installing the keyring would put a verification
# apparatus on a system where nothing is verified -- worse than the gap it
# hides. If this port ever signs its repository, it signs it with a key of its
# own, and that key is what belongs in a keyring package.
set -euo pipefail
python3 - <<'ZZPY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()

old = "  archlinux-keyring\n"
assert s.count(old) == 1, "base-devel: entree archlinux-keyring introuvable"
s = s.replace(old, "", 1)

io.open("PKGBUILD", "w", encoding="utf-8").write(s)
ZZPY
grep -q "archlinux-keyring" PKGBUILD && { echo "base-devel: archlinux-keyring survit" >&2; exit 1; }
grep -q "debugedit" PKGBUILD || { echo "base-devel: debugedit a disparu, ce n est pas voulu" >&2; exit 1; }
echo "base-devel: archlinux-keyring retire, debugedit garde"
