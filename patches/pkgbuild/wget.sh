#!/usr/bin/env bash
# wget appelle une fonction que GnuTLS a retiree.
#
#   gnutls.c:805: error: implicit declaration of function
#   'gnutls_protocol_set_priority'
#
# gnutls 3.8.13 ne la declare plus nulle part : elle ne subsiste que dans son
# ChangeLog et son chapitre de mise a niveau. wget l'appelle a cinq endroits,
# sans garde, et sa branche principale les porte encore -- l'amont n'a pas
# corrige. Les deux versions que ce portage bâtit ne s'accordent donc pas, et
# aucune mise a jour de recette n'y changera rien aujourd'hui.
#
# CE QUE WGET FAIT ICI. Il n'est pas livre pour lui-meme : `./bootstrap`
# l'appelle dans sed, grep, findutils et diffutils, et un wget qui ne demarre
# pas arrete ces quatre-la dans prepare(), sur un message qui ne parle que de
# wget. Ce dont ils ont besoin est un client HTTP qui fonctionne.
#
# OpenSSL est l'autre dorsale que wget sait utiliser, le portage la bâtit
# deja, et son en-tete comme sa bibliotheque sont dans le chroot. C'est donc
# un changement de dorsale TLS, assume et ecrit ici : le paquet diverge de
# celui d'Arch sur ce point, et seulement sur ce point.
set -euo pipefail
python3 - <<'ZZPY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()
old = "--with-ssl=gnutls"
assert s.count(old) == 1, "wget: une seule option --with-ssl attendue"
s = s.replace(old, "--with-ssl=openssl", 1)
# La dependance suit la dorsale : laisser gnutls ferait entrer dans le
# paquet une bibliotheque qu'il ne lie plus.
old = "'zlib' 'gnutls' 'libidn2'"
assert s.count(old) == 1, "wget: la dependance gnutls n est pas sous la forme attendue"
s = s.replace(old, "'zlib' 'openssl' 'libidn2'", 1)
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
ZZPY
grep -q -- "--with-ssl=openssl" PKGBUILD || {
    echo "wget: la dorsale n a pas ete changee" >&2; exit 1; }
grep -q "'gnutls'" PKGBUILD && {
    echo "wget: gnutls subsiste dans depends" >&2; exit 1; }
echo "wget: dorsale TLS openssl, gnutls ne declarant plus ce qu il appelle"
