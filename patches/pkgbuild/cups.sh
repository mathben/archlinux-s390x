#!/bin/sh
# La recette produit deux paquets : libcups, la bibliotheque cliente, et cups,
# le serveur d'impression. Seul libcups est garde.
#
# POURQUOI. pycups se compile contre cups/http.h et se lie a libcups ; c'est
# tout ce dont les pilotes d'imprimante d'Odoo et le module OCA
# base_report_to_printer ont besoin, puisqu'ils parlent a un serveur CUPS par
# IPP, local ou distant. Le paquet cups, lui, declare cups-filters, qui
# declare libppd et libcupsfilters, qui tirent poppler, qpdf et ghostscript :
# une chaine entiere pour un demon dont une instance Odoo n'a pas l'emploi.
#
# Sans ce retrait le depot ne RESOUT pas : « unable to satisfy dependency
# cups-filters required by cups ».
#
# La bibliotheque reste batie avec avahi : sans lui, dest.c reference des
# champs de struct que son propre #ifdef n'a pas definis.
python3 - <<'ZZPY'
import io, re, sys
s = io.open("PKGBUILD", encoding="utf-8").read()

m = re.search(r"^pkgname=\('libcups' 'cups'\)\s*$", s, re.M)
if not m:
    sys.exit("cups: pkgname n'a plus la forme attendue")
s = s[:m.start()] + "pkgname=('libcups')" + s[m.end():]

m2 = re.search(r"^package_cups\(\) \{.*?^\}\n", s, re.S | re.M)
if not m2:
    sys.exit("cups: package_cups() introuvable")
s = s[:m2.start()] + s[m2.end():]

io.open("PKGBUILD", "w", encoding="utf-8").write(s)
ZZPY

grep -qE "^pkgname=\('libcups'\)\s*$" PKGBUILD || {
    echo "cups: pkgname n a pas ete reduit a libcups" >&2; exit 1; }
grep -qE '^package_cups\(\)' PKGBUILD && {
    echo "cups: package_cups() subsiste" >&2; exit 1; }
grep -qE '^package_libcups\(\)' PKGBUILD || {
    echo "cups: package_libcups() a disparu" >&2; exit 1; }
echo "cups: bibliotheque cliente seule, serveur d impression ecarte"
