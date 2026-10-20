#!/usr/bin/env bash
# Compare two stages: does the later one reproduce the earlier?
#
# WHAT SELF-HOSTING MEANS HERE, precisely. Stage 3 is built by stage 2's own
# compiler, in a chroot made only of stage 2's packages. If the two agree, the
# distribution no longer owes anything to the host it started on -- what it
# produces is what it is made of.
#
# WHY NOT BYTE-FOR-BYTE. These packages are not reproducible builds and do not
# claim to be: a .pkg.tar.zst carries build dates, and objects carry paths and
# timestamps. Comparing archives would report a difference for every package
# and mean nothing. What CAN be compared is what a distribution actually
# promises:
#
#   1. the set of packages, and their versions
#   2. the files each package ships
#   3. what each package declares -- depends and provides
#
# A difference in any of those is a real difference: a file that appeared or
# vanished, a dependency that changed, a package that stopped being built. A
# difference in none of them is what "reproduces" is worth asserting about.
#
# READ THE VERDICT AS IT IS WRITTEN. `identical` here means those three agree,
# not that the bytes do.
set -euo pipefail

WORK="${WORK:-$HOME/work/arch-s390x}"
A="${A:-$WORK/repo2/s390x}"
B="${B:-$WORK/repo3/s390x}"
OUT="${OUT:-$WORK/compare-stages.txt}"

die() { echo "compare-stages: $*" >&2; exit 1; }
say() { printf '  %s\n' "$*"; }

[ -d "$A" ] || die "no repository at $A"
[ -d "$B" ] || die "no repository at $B"

# LES DEUX ETAGES NE COMPRESSENT PAS PAREIL, et une comparaison qui ne
# cherche qu'une extension n'en lit qu'un. L'etage 1 suit le makepkg.conf de
# l'hote, qui peut imposer PKGEXT='.pkg.tar.gz' ; le chroot de l'etage 2 garde
# le .pkg.tar.zst d'Arch. En ne voyant que .zst, ce script comparait ZERO
# paquet et annoncait quand meme que les etages different -- un verdict
# assure, rendu sans avoir rien lu. L'extension n'est pas un critere ici :
# c'est la façon de compresser, pas ce que le paquet contient.
_PKGGLOB='*.pkg.tar.*'

# UNE SEULE VERSION PAR PAQUET, LA PLUS RECENTE.
#
# repo-add tient la base a jour, mais le FICHIER de l'ancienne version reste
# sur le disque : un paquet rebati a un pkgver different laisse deux archives
# cote a cote. Les ramasser toutes fait apparaitre un ecart de VERSION entre
# les deux etages la ou il n'y a qu'un vieux fichier -- « compiler-rt: 22.1.8
# -> 23.1.1 » alors que les deux depots portent bien 23.1.1. Le verdict se
# lit alors comme un resultat, et n'en est pas un.
_newest() {  # <repo> -> le fichier le plus recent par paquet, un par ligne
    local f base rest name
    for f in "$1"/$_PKGGLOB; do
        [ -e "$f" ] || continue
        case "$f" in *.sig) continue ;; esac
        base="${f##*/}"
        rest="${base%.pkg.tar.*}"; rest="${rest%-*}"
        rest="${rest%-*}"; name="${rest%-*}"
        printf '%s\t%s\t%s\n' "$name" "$(stat -c %Y "$f")" "$f"
    done | sort -t$'\t' -k1,1 -k2,2nr | awk -F'\t' '!seen[$1]++ { print $3 }'
}

_names() {  # <repo> -> "name version" par ligne, une seule par paquet
    local f base rest rel ver name
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        base="${f##*/}"
        rest="${base%.pkg.tar.*}"              # ... nom-version-release-arch
        rest="${rest%-*}"                      # ... nom-version-release
        rel="${rest##*-}" ; rest="${rest%-*}"
        ver="${rest##*-}" ; name="${rest%-*}"
        printf '%s %s-%s\n' "$name" "$ver" "$rel"
    done < <(_newest "$1") | sort
}

# <repo> <nom> -> le fichier du paquet, quelle que soit sa compression, et le
# PLUS RECENT s'il y en a plusieurs -- meme raison que _newest ci-dessus : une
# ancienne archive laissee sur le disque ferait comparer la mauvaise.
_pkgfile() {
    local f best="" bt=0 t
    for f in "$1/$2"-[0-9]*.pkg.tar.*; do
        [ -e "$f" ] || continue
        case "$f" in *.sig) continue ;; esac
        t=$(stat -c %Y "$f")
        if [ -z "$best" ] || [ "$t" -gt "$bt" ]; then best="$f"; bt="$t"; fi
    done
    [ -n "$best" ] || return 1
    printf '%s\n' "$best"
}

# bsdtar plutot que `tar --use-compress-program=unzstd` : il reconnait la
# compression a la lecture, donc un .gz et un .zst se lisent du meme appel.
# Le `sort` final ecrit dans un tube que son lecteur peut fermer tot -- `diff
# -q` s'arrete a la premiere difference, `head` a sa vingtieme ligne -- et se
# plaint alors sur stderr. Une ligne « write failed: Broken pipe » par paquet
# compare noie un rapport dont c'est justement la lisibilite qui fait l'interet.
_manifest() {  # <fichier paquet> -> fichiers + declarations, trie
    {
        bsdtar -tf "$1" 2>/dev/null \
            | grep -vE '^\.(PKGINFO|BUILDINFO|MTREE)$' | sort
        bsdtar -xOf "$1" .PKGINFO 2>/dev/null \
            | grep -E '^(depend|provides|conflict|replaces) ' | sort
    } 2>/dev/null
}

: > "$OUT"
echo "== The package sets =="
_names "$A" > "$WORK/.cmp-a"
_names "$B" > "$WORK/.cmp-b"
only_a=$(comm -23 <(cut -d' ' -f1 "$WORK/.cmp-a") <(cut -d' ' -f1 "$WORK/.cmp-b"))
only_b=$(comm -13 <(cut -d' ' -f1 "$WORK/.cmp-a") <(cut -d' ' -f1 "$WORK/.cmp-b"))
say "$(wc -l < "$WORK/.cmp-a") in $(basename "$(dirname "$A")"), $(wc -l < "$WORK/.cmp-b") in $(basename "$(dirname "$B")")"
[ -n "$only_a" ] && { echo "  not rebuilt:"; echo "$only_a" | sed 's/^/        /'; }
[ -n "$only_b" ] && { echo "  new:"; echo "$only_b" | sed 's/^/        /'; }

echo "== Versions =="
vdiff=$(join "$WORK/.cmp-a" "$WORK/.cmp-b" | awk '$2 != $3 {print "        " $1 ": " $2 " -> " $3}')
if [ -z "$vdiff" ]; then say "every common package is at the same version"
else echo "  differ:"; echo "$vdiff"; fi

echo "== Contents and declarations =="
same=0; differ=0
# `ls` d un motif sans correspondance rend un statut non nul, et sous set -e une
# AFFECTATION qui capture cet echec tue le script -- ici juste avant le verdict,
# donc en silence et a l endroit ou le lecteur attend la reponse. Un `|| true`
# par capture : l absence d un fichier est une donnee, pas une erreur.
while read -r name _; do
    fa=$(_pkgfile "$A" "$name" || true)
    fb=$(_pkgfile "$B" "$name" || true)
    [ -n "$fa" ] && [ -n "$fb" ] || continue
    if diff -q <(_manifest "$fa" || true) <(_manifest "$fb" || true) >/dev/null 2>&1; then
        same=$((same + 1))
    else
        differ=$((differ + 1))
        # `diff | head` : head ferme le tube des qu il a ses vingt lignes, diff
        # recoit SIGPIPE, et sous set -e le script meurt LA -- au premier
        # paquet qui differe, c est-a-dire au seul endroit qui compte. Le bug
        # etait invisible tant que tout etait identique.
        {
            printf '=== %s ===\n' "$name"
            # head ferme le tube a vingt lignes, et le `sort` qui ecrit
            # dedans se plaint alors sur stderr -- une ligne « write failed:
            # Broken pipe » par paquet different, qui noie le rapport sans
            # rien signaler de vrai.
            diff <(_manifest "$fa" 2>/dev/null || true) \
                 <(_manifest "$fb" 2>/dev/null || true) \
                | head -20 2>/dev/null || true
        } >> "$OUT" || true
    fi
done < <(join "$WORK/.cmp-a" "$WORK/.cmp-b")
rm -f "$WORK/.cmp-a" "$WORK/.cmp-b"

say "$same identical, $differ differing"
[ "$differ" -gt 0 ] && say "differences listed in $OUT"

echo
if [ -z "$only_a" ] && [ -z "$only_b" ] && [ -z "$vdiff" ] && [ "$differ" -eq 0 ]; then
    echo "  SELF-HOSTING: the later stage reproduces the earlier one."
else
    echo "  NOT YET: the stages differ. Every line above is a thing to explain."
fi
