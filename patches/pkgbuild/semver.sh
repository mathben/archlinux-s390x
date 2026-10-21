#!/bin/sh
# Cycle d'amorçage. Le paquet npm d'Arch ne fournit pas semver : il le déclare
# en dépendance, et son lanceur s'arrête sur « Cannot find module
# semver/functions/satisfies » tant que le paquet semver n'est pas installé.
# Or le PKGBUILD de semver appelle « npm install » dans prepare(). Rien ne peut
# donc bâtir le premier des deux.
#
# L'appel est retirable sans perte : node-semver n'a AUCUNE dépendance
# d'exécution — depends=('nodejs') et rien d'autre — donc « npm install » n'y
# pose que les dépendances de développement, utiles au seul check(). Et
# package() ne lit pas node_modules : il prend les fichiers que package.json
# énumère dans « .files », tirés du dépôt git.
#
# Le crochet ne vaut donc QUE sans check(). Il refuse de s'appliquer si le
# PKGBUILD a cessé d'être celui qu'il décrit.
python3 - <<'ZZPY'
import io, sys
lines = io.open("PKGBUILD", encoding="utf-8").read().split("\n")
hit = [i for i, l in enumerate(lines) if l.strip() == "npm install"]
if len(hit) != 1:
    sys.exit("semver: attendu un seul « npm install », trouve %d" % len(hit))
i = hit[0]
# Il doit etre dans prepare(), pas ailleurs : package() ou build() s'en
# serviraient pour autre chose que les dependances de developpement.
beg = max((j for j, l in enumerate(lines[:i]) if l.startswith("prepare()")),
          default=None)
if beg is None:
    sys.exit("semver: « npm install » hors de prepare()")
end = next((j for j in range(beg, len(lines)) if lines[j].rstrip() == "}"), None)
if end is None or not (beg < i < end):
    sys.exit("semver: prepare() introuvable autour de « npm install »")
ind = lines[i][:len(lines[i]) - len(lines[i].lstrip())]
lines[i:i + 1] = [
    ind + "# « npm install » retire : il ne pose que les dependances de",
    ind + "# developpement, et npm ne tourne pas tant que ce paquet-ci manque.",
    ind + ":",
]
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lines))
ZZPY
# Le motif vise une COMMANDE — une ligne qui ne porte que « npm install » —
# et non la chaine : le commentaire pose juste au-dessus la contient, et un
# grep nu se declencherait sur son propre remplacement.
grep -qE '^[[:space:]]*npm[[:space:]]+install([[:space:]]|$)' PKGBUILD && {
    echo "semver: un appel « npm install » subsiste" >&2; exit 1; }
# package() lit package.json avec jq ; si cette lecture disparaissait, le
# paquet sortirait vide sans erreur.
grep -q "jq -r '.files\[\]' package.json" PKGBUILD || {
    echo "semver: package() ne lit plus la liste des fichiers" >&2; exit 1; }
echo "semver: npm install retire de prepare(), cycle d amorcage rompu"
