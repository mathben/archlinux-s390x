#!/usr/bin/env bash
# xz: autogen.sh without po4a.
#
#   po4a/update-po: Translated man pages were not generated.
#   ==> ERROR: A failure occurred in prepare().
#
# prepare() runs only `./autogen.sh`, and that script regenerates the translated
# man pages with po4a -- a Perl toolchain this port declined along with the rest
# of the documentation stack. xz's autogen.sh takes --no-po4a for exactly this,
# so the switch is upstream's, not ours.
set -euo pipefail
python3 - <<'ZZPY'
import io, re
lines = io.open("PKGBUILD", encoding="utf-8").read().split("\n")
hit = [i for i, l in enumerate(lines) if re.match(r"^[ \t]*\./autogen\.sh[ \t]*$", l)]
assert len(hit) == 1, "xz: expected one bare ./autogen.sh, got %d" % len(hit)
lines[hit[0]] = lines[hit[0]].rstrip() + " --no-po4a"
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lines))
ZZPY
grep -q -- "autogen.sh --no-po4a" PKGBUILD || {
    echo "xz: --no-po4a was not added" >&2; exit 1; }
echo "xz: translated man pages skipped"
