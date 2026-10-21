#!/bin/sh
# configure s'arrête sur « Package requirements ( gtk+-3.0 ) were not met ».
# La recette desactive mono et qt5 mais pas GTK, parce qu'elle produit un
# sous-paquet avahi-gtk : les outils graphiques avahi-discover, bshell, bssh
# et bvnc. Sur une machine sans serveur X, ces outils n'ont pas d'emploi, et
# GTK3 ferait entrer une pile entiere dans le portage.
#
# Ce qui reste est le paquet avahi : le demon, libavahi-client, et la
# compatibilite libdns_sd que --enable-compat-libdns_sd fournit. C'est tout
# ce dont cups a besoin — sans avahi, dest.c de cups reference des champs de
# struct que son propre #ifdef n'a pas definis.
#
# avahi-gtk disparait de pkgname, sans quoi makepkg reclamerait un paquet que
# plus rien ne produit.
python3 - <<'ZZPY'
import io, re, sys
s = io.open("PKGBUILD", encoding="utf-8").read()

m = re.search(r"^(\s*)--disable-qt5\s*$", s, re.M)
if not m:
    sys.exit("avahi: --disable-qt5 introuvable, options inattendues")
s = (s[:m.end()]
     + "\n" + m.group(1) + "--disable-gtk3"
     + "\n" + m.group(1) + "--disable-python"
     + "\n" + m.group(1) + "--disable-manpages" + s[m.end():])

# pkgname est un tableau sur plusieurs lignes. avahi-gtk porte les outils
# graphiques, avahi-bookmarks un service ecrit en Python : ni l'un ni l'autre
# ne peut etre produit sans GTK ni pygobject. Seul avahi reste.
for _sp in ("avahi-gtk", "avahi-bookmarks"):
    m2 = re.search(r"^\s*%s\s*$\n" % re.escape(_sp), s, re.M)
    if not m2:
        sys.exit("avahi: %s absent de pkgname" % _sp)
    s = s[:m2.start()] + s[m2.end():]

# Sa fonction package_ devient morte : makepkg ne l'appelle plus, mais la
# laisser ferait mentir le fichier sur ce qu'il produit.
for _sp in ("avahi-gtk", "avahi-bookmarks"):
    m3 = re.search(r"^package_%s\(\) \{.*?^\}\n" % re.escape(_sp),
                   s, re.S | re.M)
    if not m3:
        sys.exit("avahi: package_%s() introuvable" % _sp)
    s = s[:m3.start()] + s[m3.end():]

# _pick deplace des chemins vers les sous-paquets et s'arrete sur un chemin
# absent. Les neuf appels visent des fichiers que GTK, Python et xmltoman
# auraient produits : avahi-bookmarks, les outils graphiques, leurs pages de
# manuel. Rendre _pick tolerant couvre les neuf d'un coup, et ne change rien
# quand le chemin existe. Le meme idiome se retrouve dans glib2.
m4 = re.search(r"^(\s*)mv \"\$f\" \"\$d\"\s*$", s, re.M)
if not m4:
    sys.exit("avahi: le corps de _pick a change")
s = (s[:m4.start()]
     + m4.group(1) + "# Un chemin absent n'est pas une erreur : GTK, Python et\n"
     + m4.group(1) + "# les pages de manuel ne sont pas produits ici.\n"
     + m4.group(1) + '[ -e "$f" ] || continue\n'
     + m4.group(1) + 'mv "$f" "$d"'
     + s[m4.end():])

io.open("PKGBUILD", "w", encoding="utf-8").write(s)
ZZPY

grep -qE '^\s*--disable-gtk3\s*$' PKGBUILD || {
    echo "avahi: --disable-gtk3 n a pas ete pose" >&2; exit 1; }
grep -qE '^\s*--disable-python\s*$' PKGBUILD || {
    echo "avahi: --disable-python n a pas ete pose" >&2; exit 1; }
grep -qE '^\s*--disable-manpages\s*$' PKGBUILD || {
    echo "avahi: --disable-manpages n a pas ete pose" >&2; exit 1; }
grep -qE '^\s*\[ -e "\$f" \] \|\| continue\s*$' PKGBUILD || {
    echo "avahi: _pick n est pas tolerant a un chemin absent" >&2; exit 1; }
grep -qE '^\s*avahi-(gtk|bookmarks)\s*$' PKGBUILD && {
    echo "avahi: un sous-paquet retire subsiste dans pkgname" >&2; exit 1; }
# Le paquet principal doit rester : c'est lui que cups reclame.
grep -qE '^package_avahi\(\)' PKGBUILD || {
    echo "avahi: package_avahi() a disparu" >&2; exit 1; }
grep -qE '^\s*--enable-compat-libdns_sd\s*$' PKGBUILD || {
    echo "avahi: la compatibilite libdns_sd, requise par cups, a disparu" >&2; exit 1; }
echo "avahi: gtk3 desactive, sous-paquet graphique retire"
