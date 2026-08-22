#!/usr/bin/env bash
# util-linux: the man3 pages that were never built.
#
#   mv: cannot stat '<pkgdir>/usr/share/man/man3': No such file or directory
#
# util-linux renders its man pages from asciidoc, which this port does not have,
# so man3 does not exist. The util-linux-libs split moves it out of pkgdir and
# then back in -- TWO places, and removing only the first fails on the second.
#
# Both moves go. Nothing is left conditional: if the directory is never created,
# a guard around moving it is a guard around nothing, and it would read as if
# the man pages were sometimes present.
#
# Same shape as libxml2's docs split, pam's PDFs, libuv's man page and cmake's
# emacs byte-compilation: a failure on a path at the end of package(), after a
# compile that worked. Seventh time.
set -euo pipefail
python3 - <<'ZZPY'
import io, re
lines = io.open("PKGBUILD", encoding="utf-8").read().split("\n")
hit = [i for i, l in enumerate(lines)
       if re.search(r"\bman3\b", l) and l.lstrip().startswith("mv ")]
assert len(hit) == 2, "util-linux: expected two man3 moves, got %d" % len(hit)
for i in reversed(hit):
    ind = re.match(r"^[ \t]*", lines[i]).group(0)
    lines[i] = ind + ": # man3 not built: no asciidoc at either stage."
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lines))
ZZPY
if grep -qE "^[[:space:]]*mv .*\bman3\b" PKGBUILD; then
    echo "util-linux: a man3 move survived" >&2; exit 1
fi
grep -c "man3 not built" PKGBUILD | grep -qx 2 || {
    echo "util-linux: expected both moves replaced" >&2; exit 1; }
echo "util-linux: man3 moves removed (both)"
