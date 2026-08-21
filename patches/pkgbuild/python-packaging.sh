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
lines[hit[0]] = lines[hit[0]].replace("$srcdir/$_name-$pkgver/LICENSE*",
                                      "$srcdir/$pkgname/LICENSE*")
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lines))
ZZPY
grep -q 'srcdir/\$pkgname/LICENSE\*' PKGBUILD || {
    echo "python-packaging: the license path was not redirected" >&2; exit 1; }
echo "python-packaging: license taken from the bootstrap clone"
