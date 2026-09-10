#!/usr/bin/env bash
# pahole: build pahole, not ostra-cg.
#
# WHY THIS HOOK EXISTS AT ALL. pahole was built to close a hole -- linux-headers
# declares it and nothing provided it. Its pkgbase produces a SECOND package,
# ostra-cg, which draws call graphs from traces and therefore depends on
# python-matplotlib. So closing one hole opened another, one layer deeper and
# far more expensive: matplotlib wants numpy, freetype, qhull and a font stack.
#
# A repository is closed or it is not, and a package nobody here installs is
# not worth the tree behind it. ostra-cg leaves pkgname; pahole itself is
# untouched and still installs everything linux-headers asks for.
#
# FIVE PLACES, and this port has been caught by the fifth before: the pkgname
# array, the package_ function, the matplotlib line in makedepends, and the
# optdepends line in package_pahole that advertises a package that will no
# longer exist. The `mv ostra/*` inside the removed function goes with it.
#
# TO RESTORE: build matplotlib and its tree, then delete this hook.
set -euo pipefail
python3 - <<'ZZPY'
import io, re
s = io.open("PKGBUILD", encoding="utf-8").read()

old = """pkgname=(
  pahole
  ostra-cg
)"""
new = """pkgname=(
  pahole
)"""
assert s.count(old) == 1, "pahole: tableau pkgname introuvable"
s = s.replace(old, new, 1)

# La fonction entiere, de sa ligne d ouverture a l accolade en colonne 1.
m = re.search(r"\npackage_ostra-cg\(\) \{.*?\n\}\n", s, re.S)
assert m, "pahole: package_ostra-cg() introuvable"
s = s[: m.start()] + "\n" + s[m.end() :]

old = "  optdepends=('ostra-cg: Generate call graphs from encoded traces')\n"
assert s.count(old) == 1, "pahole: optdepends introuvable"
s = s.replace(old, "", 1)

old = "  python-matplotlib\n"
assert s.count(old) == 1, "pahole: makedepend matplotlib introuvable"
s = s.replace(old, "", 1)

io.open("PKGBUILD", "w", encoding="utf-8").write(s)
ZZPY
# Le garde vise la FONCTION et le TABLEAU, pas le mot « ostra ». Le PKGBUILD
# en garde deux mentions legitimes : le nom d un patch, et la ligne
#
#   _pick ostra "$pkgdir"/usr/{bin/ostra-cg,lib/python*}
#
# qui DEPLACE ces fichiers hors du paquet. Sans package_ostra-cg pour les
# reprendre, ils ne sont empaquetes nulle part -- ce qui est precisement le
# but. Un garde sur le mot condamnait la ligne qui fait le travail.
grep -q "^package_ostra" PKGBUILD && { echo "pahole: package_ostra-cg survit" >&2; exit 1; }
grep -qE "^\s+ostra-cg$" PKGBUILD && { echo "pahole: ostra-cg est encore un pkgname" >&2; exit 1; }
grep -q "matplotlib" PKGBUILD && { echo "pahole: matplotlib survit" >&2; exit 1; }
grep -q "_pick ostra" PKGBUILD || { echo "pahole: ostra-cg finirait dans pahole" >&2; exit 1; }
grep -q "package_pahole" PKGBUILD || { echo "pahole: le paquet principal a disparu" >&2; exit 1; }
echo "pahole: ostra-cg retire, matplotlib avec"
