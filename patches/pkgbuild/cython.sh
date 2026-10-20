#!/usr/bin/env bash
# cython: drop the numpy dependency.
#
# WHY IT IS DECLARED. Cython ships .pxd files that describe numpy's C API, so
# that Cython code which uses numpy arrays can `cimport numpy`. Arch names
# numpy in depends for those users.
#
# WHY IT GOES HERE. Nothing in this port compiles Cython code against numpy --
# the .pxd files stay in the package and are simply never read. What numpy
# costs is not itself: it depends on cblas and lapack, neither of which this
# port builds, and the usual provider of both is a full BLAS implementation.
# Three trees so that a file nobody opens has a library behind it.
#
# python-pygments, the other half of cython's declaration, is NOT removed: it
# is pure Python and it is built. A dependency is dropped because it costs a
# tree, never because it is merely unused.
#
# TO RESTORE: build cblas, lapack and numpy, then delete this hook. Anyone
# compiling numpy-using Cython here will need them anyway, and will find out
# with `cimport numpy` failing rather than with a broken install.
set -euo pipefail
python3 - <<'ZZPY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()

# Le tableau tient sur plusieurs lignes, sans guillemets : la ligne ENTIERE
# part, sinon il reste une indentation orpheline dans le tableau.
old = "         python-numpy\n"
assert s.count(old) == 1, "cython: ligne python-numpy introuvable"
s = s.replace(old, "", 1)

io.open("PKGBUILD", "w", encoding="utf-8").write(s)
ZZPY
grep -q "python-numpy" PKGBUILD && { echo "cython: numpy survit" >&2; exit 1; }
grep -q "python-pygments" PKGBUILD || { echo "cython: pygments a disparu" >&2; exit 1; }
echo "cython: numpy retire, pygments garde"

# ET package() RENOMME DES SCRIPTS QU'INSTALLER A DEJA NOMMES AINSI.
#
# La recette veut cygdb3 comme vrai script et cygdb comme lien, et l'obtient
# par un mv suivi d'un ln -s. Dans le chroot d'etage 3, `python -m installer`
# ecrit DIRECTEMENT cygdb3, cython3 et cythonize3 : le mv cherche un fichier
# qui n'existe pas, et package() s'arrete sur
#
#   mv: cannot stat '.../usr/bin/cygdb': No such file or directory
#
# OBSERVE, PAS DEDUIT : la roue ne contient aucun script pre-fabrique, ses
# trois points d'entree s'appellent bien cygdb, cython et cythonize, et
# installer lance seul sur cette meme roue, dans ce meme chroot, produit les
# noms suffixes. L'etage 2 avait obtenu les noms simples avec la meme version
# d'installer ; la raison de cet ecart n'est pas etablie, et n'est pas supposee
# ici.
#
# D'ou une boucle qui vise l'ETAT VOULU plutot qu'une transformation : le
# script suffixe existe, le lien existe, peu importe lequel des deux installer
# a ecrit. Elle reste juste si la recette est un jour corrigee en amont, et
# une seconde boucle verifie l'etat atteint plutot que de l'esperer.
python3 - <<'ZZPY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()
old = """  for f in cygdb cython cythonize; do
    mv "$pkgdir"/usr/bin/$f "$pkgdir"/usr/bin/${f}3
    ln -s ${f}3 "$pkgdir"/usr/bin/$f
  done"""
assert s.count(old) == 1, "cython: la boucle de renommage n est pas sous la forme attendue"
new = """  # Etat voulu, non transformation : voir patches/pkgbuild/cython.sh.
  for f in cygdb cython cythonize; do
    if [ ! -e "$pkgdir/usr/bin/${f}3" ]; then
      mv "$pkgdir/usr/bin/$f" "$pkgdir/usr/bin/${f}3"
    fi
    [ -e "$pkgdir/usr/bin/$f" ] || ln -s "${f}3" "$pkgdir/usr/bin/$f"
  done
  for f in cygdb cython cythonize; do
    [ -f "$pkgdir/usr/bin/${f}3" ] || { echo "cython: ${f}3 manquant" >&2; exit 1; }
    [ -L "$pkgdir/usr/bin/$f" ]    || { echo "cython: lien $f manquant" >&2; exit 1; }
  done"""
s = s.replace(old, new, 1)
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
ZZPY
grep -q 'Etat voulu, non transformation' PKGBUILD || {
    echo "cython: la boucle n a pas ete remplacee" >&2; exit 1; }
echo "cython: scripts suffixes et liens obtenus quel que soit le nom produit"
