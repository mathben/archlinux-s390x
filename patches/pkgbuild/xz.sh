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

# --- and no doxygen API reference ---------------------------------------------
#
# With po4a out of the way, the build got as far as
#
#   ../../../doxygen/update-doxygen: 'doxygen' command not found
#   make[4]: *** [Makefile:642: ../../../doc/api/index.html] Error 1
#
# Two documentation toolchains in one package: po4a for the translated man pages,
# doxygen for the liblzma API reference. --disable-doc is xz's own switch, and it
# was checked in configure before use -- both --disable-doc and --enable-doc are
# there.
set -euo pipefail
python3 - <<'ZZPY'
import io, re
lines = io.open("PKGBUILD", encoding="utf-8").read().split("\n")
hit = [i for i, l in enumerate(lines) if re.match(r"^[ \t]*\./configure[ \t]*\\\\?$", l)]
assert len(hit) == 1, "xz: expected one ./configure line, got %d" % len(hit)
i = hit[0]
ind = re.match(r"^[ \t]*", lines[i]).group(0)
assert lines[i].rstrip().endswith("\\"), "xz: ./configure does not continue"
lines.insert(i + 1, ind + "  --disable-doc \\")
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lines))
ZZPY
grep -A1 -E "^[[:space:]]*\./configure" PKGBUILD | grep -q -- "--disable-doc" || {
    echo "xz: --disable-doc is not on the configure line" >&2; exit 1; }
echo "xz: doxygen API reference disabled"
