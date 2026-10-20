#!/usr/bin/env bash
# One of the six packages in the Python packaging cycle. The reasoning, and the
# edit, are shared -- see lib-python-bootstrap.sh.
set -euo pipefail
source "$(dirname "$0")/lib-python-bootstrap.sh"

# LA BORNE HAUTE DE flit_core, QUE L'ETAGE 3 FAIT APPARAITRE.
#
# Le pyproject.toml demande « flit_core >=3.2,<4 » et ce portage bâtit flit_core
# 4.0.2. Invisible jusqu'ici : la sonde choisissait le batisseur embarque, qui
# emporte son propre flit_core 3.12. Dans un chroot d'etage 3, build et
# installer sont la, la sonde prend donc le chemin normal -- et la borne mord :
#
#   ERROR Missing dependencies: flit_core<4,>=3.2
#
# Un environnement MEILLEUR revele ce que l'amorçage masquait.
#
# VERIFIE AVANT D'ECRIRE CE CROCHET, et c'est la seule chose qui autorise a
# passer outre : la roue se batit sans erreur avec flit_core 4.0.2 dans ce
# chroot meme. La borne est une precaution d'amont contre une version a venir,
# pas le constat d'une incompatibilite.
#
# python-build, son voisin immediat dans la meme liste, passe deja ce drapeau.
# C'est la meme situation et desormais la meme reponse.
set -euo pipefail
python3 - <<'ZZPY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()
old = "python -m build --wheel --no-isolation"
assert s.count(old) == 1, "pyproject-hooks: un seul appel a python -m build attendu"
s = s.replace(old, "python -m build --wheel --skip-dependency-check --no-isolation", 1)
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
ZZPY
grep -q -- "--skip-dependency-check" PKGBUILD || {
    echo "pyproject-hooks: le drapeau n a pas ete pose" >&2; exit 1; }
echo "python-pyproject-hooks: borne flit_core contournee, backend verifie a l oeuvre"
