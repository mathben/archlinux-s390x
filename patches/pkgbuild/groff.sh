#!/usr/bin/env bash
# groff: one decorative figure, and no netpbm to draw it.
#
#   program 'xpmtoppm' is missing; can't generate doc/gnu.eps
#   make[2]: *** [Makefile:19801: doc/gnu.eps] Error 1
#
# xpmtoppm belongs to netpbm. What it produces is the GNU logo, as EPS, for
# groff's own manual -- and getting it would mean packaging netpbm and the image
# libraries under it (libjpeg-turbo, libpng, libtiff, jbigkit), none of which
# anything else in this bootstrap wants.
#
# NO CONFIGURE SWITCH EXISTS: groff's configure has neither --without-doc nor
# --disable-doc, so there was nothing to turn off. Adding an invented flag would
# have been worse than useless -- autoconf merely warns about options it does not
# know, the build would have failed identically, and the hook's own check would
# have passed.
#
# The Makefile is generated, so it is edited after configure and before make. The
# variable is emptied rather than the rule patched, because the INSTALL side is
# already tolerant:
#
#   if test -f "$$d/gnu.eps"; then ... fi
#
# so with nothing built, nothing is installed and nothing complains. One line,
# and the only one whose absence the rest of the Makefile already handles.
set -euo pipefail
python3 - <<'ZZPY'
import io, re
lines = io.open("PKGBUILD", encoding="utf-8").read().split("\n")
mk = [i for i, l in enumerate(lines) if re.match(r"^[ \t]*make[ \t]*$", l)]
assert len(mk) >= 1, "groff: no bare `make` line found in build()"
i = mk[0]
ind = re.match(r"^[ \t]*", lines[i]).group(0)
lines[i:i] = [
    ind + "# doc/gnu.eps needs xpmtoppm from netpbm, which this port does not",
    ind + "# package. The install side already skips the file when it is absent.",
    ind + 'sed -i "s|^DOC_GNU_EPS = doc/gnu.eps$|DOC_GNU_EPS =|" Makefile',
    ind + 'grep -q "^DOC_GNU_EPS =$" Makefile',
]
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lines))
ZZPY
grep -q "DOC_GNU_EPS" PKGBUILD || { echo "groff: the figure was not dropped" >&2; exit 1; }
# The grep inside build() is the real check: it runs against the generated
# Makefile and fails the build if the variable was not what this hook expects.
grep -q 'grep -q "\^DOC_GNU_EPS =\$" Makefile' PKGBUILD || {
    echo "groff: the in-build verification is missing" >&2; exit 1; }
echo "groff: GNU logo figure dropped (no netpbm)"
