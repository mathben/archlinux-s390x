#!/bin/sh
# La recette produit trois paquets : cloud-guest-utils (growpart, ec2metadata,
# vcs-run), cloud-image-utils (cloud-localds et ses voisins) et cloud-utils,
# un meta-paquet qui ne fait que dependre des deux autres. Seul
# cloud-guest-utils est garde.
#
# POURQUOI. growpart est la seule chose attendue ici. cloud-init l appelle
# pour agrandir la partition racine AVANT d agrandir le systeme de fichiers
# qu elle porte : sans resizer, cc_growpart ecrit une ligne DEBUG et rend la
# main, et l invite demarre a la taille de l image sur un disque que le
# deploiement a deja agrandi. C est un script /bin/sh au-dessus de sfdisk,
# partx et blkid, tous deja presents.
#
# cloud-image-utils declare cdrtools, qemu-img et wget, qui ne sont pas dans
# ce portage : le garder empeche le depot de RESOUDRE, comme cups le faisait
# avec cups-filters. Le meta-paquet declare les deux autres, donc il part
# avec celui qui s en va.
python3 - <<'ZZPY'
import io, re, sys
s = io.open("PKGBUILD", encoding="utf-8").read()
m = re.search(
    r"^pkgname=\(cloud-utils cloud-guest-utils cloud-image-utils\)\s*$", s, re.M
)
if not m:
    sys.exit("cloud-utils: pkgname n'a plus la forme attendue")
s = s[: m.start()] + "pkgname=(cloud-guest-utils)" + s[m.end() :]
for nom in ("cloud-utils", "cloud-image-utils"):
    m2 = re.search(r"^package_%s\(\) \{.*?^\}\n" % re.escape(nom), s, re.S | re.M)
    if not m2:
        sys.exit("cloud-utils: package_%s() introuvable" % nom)
    s = s[: m2.start()] + s[m2.end() :]
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
ZZPY
grep -qE '^pkgname=\(cloud-guest-utils\)\s*$' PKGBUILD || {
    echo "cloud-utils: pkgname n a pas ete reduit" >&2; exit 1; }
grep -qE '^package_cloud-utils\(\)' PKGBUILD && {
    echo "cloud-utils: le meta-paquet subsiste" >&2; exit 1; }
grep -qE '^package_cloud-image-utils\(\)' PKGBUILD && {
    echo "cloud-utils: cloud-image-utils subsiste" >&2; exit 1; }
grep -qE '^package_cloud-guest-utils\(\)' PKGBUILD || {
    echo "cloud-utils: package_cloud-guest-utils() a disparu" >&2; exit 1; }
echo "cloud-utils: growpart seul, meta-paquet et cloud-image-utils ecartes"
