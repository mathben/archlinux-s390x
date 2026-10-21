#!/bin/sh
# www.open-mpi.org/software/... ne sert plus les archives : il rend 504 en
# moins d'une seconde, donc sans attendre quoi que ce soit — une passerelle
# repond a la place de l'origine, et les quatre tentatives de makepkg
# echouent toutes de la meme facon.
#
# download.open-mpi.org/release/... sert la MEME archive : les sommes de
# controle du PKGBUILD restent valides et ne sont pas touchees. Si un jour
# elles ne correspondaient plus, makepkg le dirait — c'est le garde-fou qui
# distingue un changement d'adresse d'un changement de contenu.
python3 - <<'ZZPY'
import io, sys
s = io.open("PKGBUILD", encoding="utf-8").read()
vieux = "https://www.open-mpi.org/software/hwloc/v${pkgver%.*}/downloads/"
neuf = "https://download.open-mpi.org/release/hwloc/v${pkgver%.*}/"
if s.count(vieux) != 1:
    sys.exit("hwloc: attendue une seule adresse www.open-mpi.org, trouve %d"
             % s.count(vieux))
io.open("PKGBUILD", "w", encoding="utf-8").write(s.replace(vieux, neuf))
ZZPY

grep -q "download.open-mpi.org/release/hwloc" PKGBUILD || {
    echo "hwloc: l adresse n a pas ete remplacee" >&2; exit 1; }
# Les sommes doivent survivre : une archive non verifiee entrerait dans le
# depot sans que rien ne le signale.
grep -qE "^sha512sums=\('[0-9a-f]{128}'\)" PKGBUILD || {
    echo "hwloc: la somme sha512 a disparu ou change de forme" >&2; exit 1; }
echo "hwloc: archive prise sur download.open-mpi.org, sommes inchangees"
