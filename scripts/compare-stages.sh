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

_names() {  # <repo> -> "name version" par ligne
    local f
    for f in "$1"/*.pkg.tar.zst; do
        [ -e "$f" ] || continue
        f="${f##*/}"
        # nom-version-release-arch.pkg.tar.zst ; le nom peut porter des tirets.
        local rest="${f%-*.pkg.tar.zst}"          # ... nom-version-release
        local rel="${rest##*-}" ; rest="${rest%-*}"
        local ver="${rest##*-}" ; local name="${rest%-*}"
        printf '%s %s-%s\n' "$name" "$ver" "$rel"
    done | sort
}

_manifest() {  # <fichier paquet> -> fichiers + declarations, trie
    tar --use-compress-program=unzstd -tf "$1" 2>/dev/null \
        | grep -vE '^\.(PKGINFO|BUILDINFO|MTREE)$' | sort
    tar --use-compress-program=unzstd -xOf "$1" .PKGINFO 2>/dev/null \
        | grep -E '^(depend|provides|conflict|replaces) ' | sort
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
    fa=$(ls "$A/$name"-[0-9]*.pkg.tar.zst 2>/dev/null | head -1 || true)
    fb=$(ls "$B/$name"-[0-9]*.pkg.tar.zst 2>/dev/null | head -1 || true)
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
            diff <(_manifest "$fa" || true) <(_manifest "$fb" || true) \
                | head -20 || true
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
