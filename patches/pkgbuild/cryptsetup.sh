#!/usr/bin/env bash
# cryptsetup: no asciidoctor, so no rendered man pages.
#
#   configure: error: Building man pages requires asciidoctor installed.
#
# asciidoctor is Ruby. Packaging Ruby to render cryptsetup's man pages is the
# largest of the three documentation closures this port declined, and the least
# justified: the error names the flag that turns it off.
set -euo pipefail
python3 - <<'ZZPY'
import io, re
lines = io.open("PKGBUILD", encoding="utf-8").read().split("\n")
hit = [i for i, l in enumerate(lines) if re.match(r"^[ \t]*\./configure\b", l)]
assert len(hit) == 1, "cryptsetup: expected one ./configure, got %d" % len(hit)
i = hit[0]
indent = re.match(r"^[ \t]*", lines[i]).group(0)
assert lines[i].rstrip().endswith("\\"), "cryptsetup: ./configure does not continue"
lines.insert(i + 1, indent + "    --disable-asciidoc \\")
out = [l.replace(" 'asciidoctor'", "") if "makedepends" in l else l for l in lines]
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(out))
ZZPY
grep -A1 -E "^[[:space:]]*\./configure" PKGBUILD | grep -q -- '--disable-asciidoc' || {
    echo "cryptsetup: the flag is not on ./configure" >&2; exit 1; }
echo "cryptsetup: man pages disabled"
