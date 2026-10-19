#!/usr/bin/env bash
# One of the six packages in the Python packaging cycle. The reasoning, and the
# edit, are shared -- see lib-python-bootstrap.sh.
set -euo pipefail
source "$(dirname "$0")/lib-python-bootstrap.sh"

# The license install assumes the NON-bootstrap layout, unconditionally.
#
#   install -vDm644 -t "$pkgdir/usr/share/licenses/$pkgname" \
#       $srcdir/$_name-$pkgver/LICENSE*
#
# sits outside the `if (( _bootstrap == 0 ))`, but with _bootstrap=1 the source
# array is a set of git clones and there is no packaging-26.3 directory at all:
#
#   install: cannot stat '.../src/packaging-26.3/LICENSE*'
#
# The clone is at $srcdir/python-packaging, and it carries LICENSE,
# LICENSE.APACHE and LICENSE.BSD. The other five PKGBUILDs handle this by
# naming a bootstrap-specific path in their else branch; this one just misses
# it, so the fix follows their shape rather than inventing one.
python3 - <<'ZZPY'
import io, re
lines = io.open("PKGBUILD", encoding="utf-8").read().split("\n")
hit = [i for i, l in enumerate(lines) if "LICENSE*" in l and "$_name-$pkgver" in l]
assert len(hit) == 1, "python-packaging: expected one license install, got %d" % len(hit)
# BOTH LAYOUTS, because _bootstrap is now a probe rather than a constant
# (see lib-python-bootstrap.sh). With the vendored builder the sources are git
# clones under $srcdir/$pkgname; without it they are the release tarball under
# $srcdir/$_name-$pkgver. Hardcoding either one breaks the other, and the first
# version of this hook hardcoded the clone -- correct only while _bootstrap was
# always 1.
lines[hit[0]] = re.sub(
    r"\$srcdir/\$_name-\$pkgver/LICENSE\*",
    '"$srcdir/$pkgname"/LICENSE* "$srcdir/$_name-$pkgver"/LICENSE*',
    lines[hit[0]])
# install -t with two globs would fail on whichever does not exist, so the
# whole line becomes a loop over what is actually there.
ind = re.match(r"^[ \t]*", lines[hit[0]]).group(0)
lines[hit[0]:hit[0] + 1] = [
    ind + '# The sources are a git clone under $pkgname when the vendored builder',
    ind + '# is used, and the release tarball otherwise. Take whichever exists.',
    ind + 'for _lic in "$srcdir/$pkgname"/LICENSE* "$srcdir/$_name-$pkgver"/LICENSE*; do',
    ind + '  # `|| continue`, et non `&& install` : ce que rend package() est le',
    ind + '  # statut de sa derniere commande, donc de la boucle, donc de sa',
    ind + '  # derniere iteration. Le second motif ne correspond a rien sur la',
    ind + '  # branche du batisseur : le test echoue, et makepkg lit un package()',
    ind + '  # en echec sans une ligne derreur a montrer. Avec || continue, la',
    ind + '  # boucle finit sur un continue ou un install, nuls tous les deux.',
    ind + '  [ -f "$_lic" ] || continue',
    ind + '  install -vDm644 "$_lic" -t "$pkgdir/usr/share/licenses/$pkgname"',
    ind + 'done',
]
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lines))
ZZPY
grep -q 'Take whichever exists' PKGBUILD || {
    echo "python-packaging: the license loop was not inserted" >&2; exit 1; }
# Matched against what is actually written -- the inserted line quotes the
# directory, `"$srcdir/$_name-$pkgver"/LICENSE*`, so a pattern expecting the
# slash to follow $pkgver directly finds nothing. The first version of this guard
# did exactly that and failed on a correct file.
grep -q '_name-\$pkgver"/LICENSE\*' PKGBUILD || {
    echo "python-packaging: the tarball layout was dropped" >&2; exit 1; }
# La boucle doit finir sur un statut nul, sans quoi package() echoue en
# silence. Le controle porte sur la forme ecrite, seule a le garantir.
grep -q '\[ -f "\$_lic" \] || continue' PKGBUILD || {
    echo "python-packaging: la boucle peut rendre un statut non nul" >&2; exit 1; }
echo "python-packaging: license taken from the bootstrap clone"
