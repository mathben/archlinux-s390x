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

# LE PATCH EST FABRIQUÉ À LA DEMANDE, DONC SA SOMME NE TIENT PAS.
#
# La troisième source n est pas un fichier : c est une URL que cgit calcule
# à chaque requête,
#
#   .../autoconf-archive.git/patch/?id=241f7ae5...
#
# et ses octets varient -- en-têtes, version de git, horodatage. Le tarball
# de version, lui, est un vrai fichier et reste vérifié : il a passé le
# contrôle dans la même passe où le patch a échoué.
#
#   autoconf-archive-2024.10.16.tar.xz ... Passed
#   0001_fix_AX_CXX_COMPILE_STDCXX.patch ... FAILED
#
# SKIP sur CETTE entrée seulement. C est la raison pour laquelle le portage
# ne coupe plus --skipchecksums globalement : une source instable se traite
# là où elle est, pas en aveuglant les 228 autres.
old = """'4bcc7a56332cd4f4f25fc9b1a67e8a3500e3bb6ea4d88ce1cc0fce31d4e7ea7f'"""
assert s.count(old) == 1, "autoconf-archive: la somme du patch est introuvable"
# Pas de commentaire en ligne : la liste se ferme par une parenthèse sur la
# même ligne, et le dièse l'avalerait.
s = s.replace(old, "'SKIP'", 1)

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
