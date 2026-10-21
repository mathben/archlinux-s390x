#!/bin/sh
# ninja declare gtest en makedepends. Avec --nodeps rien ne l'installe, et le
# port ne bâtit pas ce paquet : cmake ne trouve donc pas GTest, le télécharge
# par FetchContent, le bâtit, et `cmake --install` le dépose dans $pkgdir. Le
# paquet emporte alors 47 fichiers qui ne lui appartiennent pas -- en-têtes
# gmock et gtest, bibliothèques, fichiers cmake.
#
# Le défaut n'est pas seulement du bruit : il OSCILLE d'un étage à l'autre.
# Un ninja contaminé installé dans le chroot suivant y fournit
# /usr/lib/cmake/GTest/GTestConfig.cmake ; cmake trouve alors GTest et ne
# vendorise rien, donc l'étage suivant produit un ninja propre, qui prive
# l'étage d'après de GTest, qui contamine à nouveau. Deux étages consécutifs
# ne peuvent pas être identiques tant que la sortie dépend de ce qui se
# trouve dans le chroot.
#
# Le retrait en fin de package() rend la sortie indépendante du chroot : avec
# ou sans GTest, le paquet porte les mêmes fichiers.
python3 - <<'ZZPY'
import io, re
src = io.open("PKGBUILD", encoding="utf-8").read()
lines = src.split("\n")
# La derniere accolade en colonne 0 ferme package(), qui est la derniere
# fonction du fichier. Chercher `}` seul plutot que la fin du fichier : un
# PKGBUILD peut finir par des lignes vides.
close = max(i for i, l in enumerate(lines) if l.rstrip() == "}")
assert "package()" in "\n".join(lines[:close]), "ninja: package() introuvable"
lines[close:close] = [
    "",
    "  # googletest, vendorise par cmake quand GTest manque, s'installe dans",
    "  # $pkgdir avec le reste. Un paquet ninja ne fournit pas ces fichiers :",
    "  # les retirer rend la sortie identique avec ou sans GTest dans le chroot.",
    '  rm -rf "$pkgdir/usr/include/gmock" "$pkgdir/usr/include/gtest" \\',
    '         "$pkgdir/usr/lib/cmake/GTest" "$pkgdir/usr/lib/cmake/GMock"',
    '  rm -f "$pkgdir"/usr/lib/libgmock*.a "$pkgdir"/usr/lib/libgtest*.a',
    '  rm -f "$pkgdir"/usr/lib/pkgconfig/gmock*.pc "$pkgdir"/usr/lib/pkgconfig/gtest*.pc',
    "  # Un repertoire que le retrait vide reste, et un repertoire vide est",
    "  # lui-meme une difference entre deux etages. rmdir sur un repertoire non",
    "  # vide echoue, et son statut serait celui de package() : il est donc",
    "  # neutralise. /usr/include, /usr/lib/cmake et /usr/lib/pkgconfig",
    "  # appartiennent a d'autres paquets des qu'ils portent autre chose.",
    '  rmdir "$pkgdir/usr/include" "$pkgdir/usr/lib/cmake" \\',
    '        "$pkgdir/usr/lib/pkgconfig" 2>/dev/null || true',
]
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lines))
ZZPY
grep -q 'usr/include/gmock' PKGBUILD || {
    echo "ninja: le retrait de googletest n'a pas ete insere" >&2; exit 1; }
# Le retrait doit se trouver DANS package(), apres le cmake --install qui
# depose les fichiers. Un bloc insere ailleurs ne verrait pas $pkgdir rempli.
python3 - <<'ZZPY'
import io, sys
lines = io.open("PKGBUILD", encoding="utf-8").read().split("\n")
try:
    beg = next(i for i, l in enumerate(lines) if l.startswith("package()"))
    inst = next(i for i, l in enumerate(lines) if "cmake --install" in l)
    rm = next(i for i, l in enumerate(lines) if "usr/include/gmock" in l)
except StopIteration:
    sys.exit("ninja: PKGBUILD inattendu")
if not beg < inst < rm:
    sys.exit("ninja: le retrait ne suit pas cmake --install dans package()")
ZZPY
echo "ninja: googletest vendorise retire de \$pkgdir"
