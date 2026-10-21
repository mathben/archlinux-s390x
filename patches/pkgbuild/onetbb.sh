#!/bin/sh
# TBB4PY, le module Python « tbb », se bâtit en appelant pip, que le portage
# n'a pas : la construction s'arrête sur « No module named pip ». Fournir pip
# demande docutils, qui en demande d'autres — une chaîne entière pour un
# module qu'aucun paquet du portage n'importe.
#
# Le cœur C++ se bâtit SANS défaut : la cible test_handle_perror se compile et
# se lie avant que python_build n'échoue. Et c'est lui seul dont manifold3d a
# besoin : il cherche tbb par pkg-config et se lie à libtbb.
#
# La divergence est donc le module Python et rien d'autre. Elle est inscrite
# dans TODO.md, section Deferred : elle revient dès que le portage a pip.
python3 - <<'ZZPY'
import io, sys
lines = io.open("PKGBUILD", encoding="utf-8").read().split("\n")
hit = [i for i, l in enumerate(lines) if "TBB4PY_BUILD" in l]
if len(hit) != 1:
    sys.exit("onetbb: attendu un seul TBB4PY_BUILD, trouve %d" % len(hit))
i = hit[0]
if ":BOOL='ON'" not in lines[i]:
    sys.exit("onetbb: TBB4PY_BUILD n'est plus a ON, PKGBUILD inattendu")
lines[i] = lines[i].replace(":BOOL='ON'", ":BOOL='OFF'")
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lines))
ZZPY

grep -qE "TBB4PY_BUILD:BOOL='OFF'" PKGBUILD || {
    echo "onetbb: TBB4PY_BUILD n a pas ete mis a OFF" >&2; exit 1; }
# Le reste de la configuration doit survivre : si cmake n'etait plus appele,
# le paquet sortirait vide sans que rien ne le signale.
grep -qE '^\s*cmake -B build' PKGBUILD || {
    echo "onetbb: l appel a cmake a disparu" >&2; exit 1; }
echo "onetbb: TBB4PY desactive, bibliotheque C++ inchangee"
