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
# Two documentation toolchains in one package: po4a above for the translated man
# pages, doxygen for the liblzma API reference.
#
#   ../../../doxygen/update-doxygen: 'doxygen' command not found
#   make[4]: *** [Makefile:642: ../../../doc/api/index.html] Error 1
#
# THE FLAG WAS ALREADY THERE, AND LOST. The first version of this section
# inserted --disable-doxygen right after ./configure, and config.log recorded what
# actually happened:
#
#   $ ./configure --disable-doc --disable-doxygen --prefix=/usr \
#       --disable-rpath --enable-doxygen --enable-werror
#
# The PKGBUILD passes --enable-doxygen further along the same line, and autoconf
# takes the LAST occurrence. The port had already learned this from the other
# side -- the arch-meson wrapper APPENDS --auto-features auto precisely so it
# wins -- and this got it backwards.
#
# The existing option is flipped in place rather than a second one added. One
# statement per decision: two contradictory flags on one command line is how the
# next reader spends an hour in config.log.
#
# Note for later: --enable-werror is on that same line. It has not bitten yet.
set -euo pipefail
python3 - <<'ZZPY'
import io, re
lines = io.open("PKGBUILD", encoding="utf-8").read().split("\n")
hit = [i for i, l in enumerate(lines) if re.search(r"--enable-doxygen\b", l)]
assert len(hit) == 1, "xz: expected one --enable-doxygen, got %d" % len(hit)
lines[hit[0]] = lines[hit[0]].replace("--enable-doxygen", "--disable-doxygen")
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lines))
ZZPY
grep -q -- "--enable-doxygen" PKGBUILD && { echo "xz: --enable-doxygen survived" >&2; exit 1; }
grep -q -- "--disable-doxygen" PKGBUILD || { echo "xz: doxygen not disabled" >&2; exit 1; }
# One occurrence only: a line carrying both would be decided by position.
n=$(grep -c -- "--disable-doxygen" PKGBUILD)
[ "$n" = 1 ] || { echo "xz: expected 1 --disable-doxygen, found $n" >&2; exit 1; }
echo "xz: doxygen disabled by flipping the flag the PKGBUILD already passes"
