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

# Les sommes de la branche du batisseur sont recalculees par
# lib-python-bootstrap.sh, qui porte la meme faute pour les six.

# LE CHEMIN DEVINE, TROISIEME FOIS -- voir patches/pkgbuild/python-installer.sh
# et python-certifi.sh, qui portent la meme correction.
#
# package() demande a l'interpreteur ou vont les paquets et efface les entrees
# Windows la-bas :
#
#   local site_packages=$(python -c "import site; print(site.getsitepackages()[0])")
#   rm "$pkgdir/$site_packages/$_name"/*.exe
#
# Les deux n'ont aucune raison de s'accorder. Le batisseur embarque installe
# selon son propre schema, pas selon ce que site.py annonce, et le motif ne
# correspond alors a rien : il passe tel quel, et rm s'arrete sur un chemin
# portant une etoile non developpee. Chercher les fichiers la ou ils sont ne
# demande aucun interpreteur et vaut dans toutes les dispositions.
python3 - <<'ZZPY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()
old = 'rm "$pkgdir/$site_packages/$_name"/*.exe'
assert s.count(old) == 1, "setuptools: la ligne rm des .exe est introuvable"
s = s.replace(old, 'find "$pkgdir" -path "*/$_name/*.exe" -delete', 1)
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
ZZPY
grep -q 'site_packages/\$_name' PKGBUILD && {
    echo "python-setuptools: le chemin devine survit" >&2; exit 1; }
grep -q 'path "\*/\$_name/\*.exe" -delete' PKGBUILD || {
    echo "python-setuptools: la recherche n a pas ete posee" >&2; exit 1; }
echo "python-setuptools: .exe retires par find, pas par un chemin devine"

# CE QUE LE PAQUET PRODUIT NE PORTE PAS LA VERSION QU'IL ANNONCE.
#
# Le batisseur embarque emporte sa PROPRE copie de setuptools, plus ancienne
# que le pkgver de la recette, et c'est elle qui est installee. Le paquet
# s'annonce donc a la version d'amont tout en livrant celle du batisseur --
# le meme ecart que lib-python-bootstrap.sh decrit pour packaging, a ceci
# pres qu'ici la sonde ne peut pas l'eviter : ce paquet DOIT prendre la
# branche du batisseur, pour la raison donnee plus haut.
#
# Sans consequence tant qu'aucune recette ne declare un plancher superieur a
# ce que le batisseur emporte -- le plus haut rencontre est setuptools>=80.
# Une recette qui exigerait davantage serait satisfaite sur le papier et pas
# en fait, et l'echec surgirait ailleurs, chez un consommateur. Le controle
# tient en une ligne, sur le paquet bati :
#
#   bsdtar -xOf <paquet> | ... setuptools-*.dist-info/METADATA
