#!/usr/bin/env bash
# autoconf-archive: le maître GNU plutôt que son répartiteur.
#
# ftpmirror.gnu.org ne sert rien lui-même : il redirige vers un miroir tiré au
# sort, et un miroir en panne rend une erreur qui ressemble à une source
# disparue.
#
#   curl: (22) The requested URL returned error: 502
#   curl: (22) The requested URL returned error: 504     (le lendemain)
#
# Deux codes, deux miroirs, une même archive intacte derrière. ftp.gnu.org est
# la source canonique et répond : 677 768 octets, sha256 7bcd5d00…a57363, soit
# EXACTEMENT ce que le PKGBUILD attend. Vérifié avant d'écrire ce crochet, et
# c'est la seule chose qui autorise à changer une URL de source.
#
# LA DIFFÉRENCE AVEC libaio, dont la source a disparu le même jour : là, le
# tarball que Debian propose porte une AUTRE somme, donc c'est un autre
# fichier, et aucune commodité ne justifie de le livrer sous un nom qui promet
# celui d'Arch. Ici c'est le même fichier, plus près de sa source.
#
# CE QUE ÇA COÛTE : on perd la répartition de charge que ftpmirror organise.
# Pour un portage qui bâtit ce paquet quelques fois par an, c'est un prix qui
# ne se mesure pas ; pour GNU, un miroir qui répond vaut mieux qu'un tirage au
# sort qui échoue.
set -euo pipefail
python3 - <<'ZZPY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()

# L URL est CONSTRUITE, pas ecrite : "https://ftpmirror.gnu.org/${pkgname}/..."
# Un crochet qui cherche l URL telle qu elle apparait dans le message d erreur
# de curl ne la trouve donc pas dans le PKGBUILD -- l erreur montre le
# resultat, le fichier montre la recette.
old = "https://ftpmirror.gnu.org/${pkgname}/"
new = "https://ftp.gnu.org/gnu/${pkgname}/"
assert s.count(old) >= 1, "autoconf-archive: URL ftpmirror introuvable"
s = s.replace(old, new)

io.open("PKGBUILD", "w", encoding="utf-8").write(s)
ZZPY
grep -q "ftpmirror.gnu.org" PKGBUILD && {
    echo "autoconf-archive: le repartiteur survit" >&2; exit 1; }
# Le garde vise la RECETTE, pas le resultat : le PKGBUILD ecrit
# ftp.gnu.org/gnu/${pkgname}, jamais le nom developpe. Chercher la forme
# developpee, c est relire l URL du message d erreur au lieu du fichier -- la
# meme confusion que la substitution ci-dessus vient d eviter.
grep -q 'ftp.gnu.org/gnu/${pkgname}' PKGBUILD || {
    echo "autoconf-archive: l URL du maitre n a pas ete posee" >&2; exit 1; }
echo "autoconf-archive: source prise sur ftp.gnu.org"
