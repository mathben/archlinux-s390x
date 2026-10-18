#!/usr/bin/env bash
# La troisieme source n est pas un fichier publie : c est un commit rendu en
# rustine par l hebergeur, a l adresse
#
#   https://github.com/<projet>/commit/<empreinte>.patch
#
# Le contenu du commit ne bouge pas ; sa MISE EN FORME si -- en-tete du
# courriel, signature finale, version de git qui l a produite. La somme
# enregistree par la recette finit donc par ne plus correspondre, sans que
# rien d anormal se soit produit :
#
#   zlib-1.3.2.tar.xz ... Passed
#   36ff1be4....patch ... FAILED
#
# VERIFIE AVANT D ECRIRE CE CROCHET, et c est ce qui autorise le SKIP : la
# copie de l hote et celle du chroot sont identiques, octet pour octet, et
# toutes deux different de la somme attendue. Deux telechargements concordants
# a des heures differentes ne decrivent pas une corruption, mais une recette
# dont la somme a vieilli. La rustine porte un commit signe qui installe
# ints.h dans contrib/minizip.
#
# SKIP sur CETTE entree seulement -- le tarball de version reste verifie, et
# il passe. C est la raison pour laquelle ce portage ne coupe plus
# --skipchecksums globalement : une source instable se traite la ou elle est.
#
# LA RECETTE PORTE LA PREUVE ELLE-MEME. Elle a DEUX rustines de commit, et
# la seconde se termine par ?full_index=1 -- le parametre qui demande a
# l hebergeur un rendu deterministe, avec les empreintes de blob completes.
# C est exactement celle qui passe sa somme ; celle qui n a pas le parametre
# est celle qui derive. Le SKIP reste donc etroit : il vise une adresse qui
# se termine par .patch, et laisse verifiee celle qui demande la stabilite.
#
# Le motif vise la CLASSE et non ce commit-ci. Une recette qui ajoute une
# rustine de commit sans ce parametre sera couverte sans retouche.
set -euo pipefail
python3 - <<'ZZPY'
import io, re
s = io.open("PKGBUILD", encoding="utf-8").read()
m = re.search(r'^[a-z_][a-z0-9_]*\(\)\s*\{', s, re.M)
assert m, "zlib: aucune fonction ou ancrer le SKIP"
add = (
    "# Une rustine rendue a l adresse d un commit : sa mise en forme varie,\n"
    "# pas son contenu. Voir patches/pkgbuild/zlib.sh.\n"
    "_n=0\n"
    "for _i in \"${!source[@]}\"; do\n"
    "  case \"${source[$_i]}\" in\n"
    "    *://*/commit/*.patch)\n"
    "      for _a in md5sums sha1sums sha256sums sha512sums b2sums; do\n"
    "        declare -p \"$_a\" >/dev/null 2>&1 || continue\n"
    "        eval \"$_a[$_i]=SKIP\"\n"
    "      done\n"
    "      _n=$((_n + 1)) ;;\n"
    "  esac\n"
    "done\n"
    "(( _n >= 1 )) || { echo 'zlib: aucune rustine de commit trouvee' >&2; exit 1; }\n"
    "unset _i _a _n\n\n"
)
s = s[:m.start()] + add + s[m.start():]
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
ZZPY
grep -q "commit/\*.patch" PKGBUILD || {
    echo "zlib: le SKIP cible n a pas ete pose" >&2; exit 1; }
# Le controle qui compte : la rustine est SKIP, le tarball ne l est pas.
bash -c 'CARCH=s390x; source ./PKGBUILD >/dev/null 2>&1
  for i in "${!source[@]}"; do
    case "${source[$i]}" in
      *://*/commit/*.patch)
        [ "${sha512sums[$i]}" = SKIP ] || { echo "zlib: la rustine n est pas SKIP" >&2; exit 1; } ;;
      *.tar.*)
        case "${source[$i]}" in *.asc) continue ;; esac
        [ "${sha512sums[$i]}" != SKIP ] || { echo "zlib: le tarball a perdu sa somme" >&2; exit 1; } ;;
    esac
  done' || exit 1
echo "zlib: SKIP sur la rustine de commit, tarball toujours verifie"
