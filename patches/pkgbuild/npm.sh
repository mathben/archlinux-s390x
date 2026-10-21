#!/bin/sh
# Cycle d'amorçage, en trois paquets. npm embarque node-gyp, nopt et semver
# dans son propre node_modules ; son package() les SUPPRIME, parce qu'Arch les
# distribue séparément. Le npm installé ne démarre donc plus sans eux —
# « Cannot find module nopt » — alors que les package() de nopt et node-gyp
# appellent « npm install -g ». Sur une Arch déjà installée les trois viennent
# du dépôt ; sur un portage qui part de rien, aucun des quatre ne peut naître.
#
# EL_NPM_BOOTSTRAP=1 garde les copies embarquées : le npm produit se suffit à
# lui-même et sert à bâtir les trois autres. Le npm définitif se rebâtit
# ensuite SANS la variable, et il est alors identique à celui d'Arch.
#
#   EL_NPM_BOOTSTRAP=1 ... build-stage2.sh npm      # npm qui s'amorce
#   ...                    build-stage2.sh nodejs-nopt node-gyp
#   ...                    build-stage2.sh npm      # npm definitif
#
# Sans la variable le crochet ne touche à rien : le PKGBUILD reste celui
# d'Arch, ce qui est l'état voulu une fois l'amorçage fini.
[ "${EL_NPM_BOOTSTRAP:-}" = "1" ] || {
    echo "npm: pas d amorcage, PKGBUILD inchange"; exit 0; }

python3 - <<'ZZPY'
import io, sys
lines = io.open("PKGBUILD", encoding="utf-8").read().split("\n")
hit = [i for i, l in enumerate(lines)
       if l.strip() == "rm -r node_modules/{node-gyp,nopt,semver}"]
if len(hit) != 1:
    sys.exit("npm: attendu un seul retrait des modules embarques, trouve %d"
             % len(hit))
i = hit[0]
ind = lines[i][:len(lines[i]) - len(lines[i].lstrip())]
lines[i:i + 1] = [
    ind + "# EL_NPM_BOOTSTRAP : les copies embarquees restent, sans quoi npm",
    ind + "# ne demarre pas et rien ne peut bâtir les paquets qui les",
    ind + "# remplacent. Le npm definitif se rebatit sans la variable.",
    ind + ": # " + lines[i].strip(),
]
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lines))
ZZPY

# Le motif vise une COMMANDE, pas la chaine : le commentaire insere juste
# au-dessus cite la ligne retiree, et un grep nu se declencherait dessus.
grep -qE '^[[:space:]]*rm[[:space:]]+-r[[:space:]]+node_modules/' PKGBUILD && {
    echo "npm: le retrait des modules embarques subsiste" >&2; exit 1; }
echo "npm: modules embarques conserves pour l amorcage"
