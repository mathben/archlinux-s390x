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
# TWO options, not one. --disable-doc was added first and doxygen still ran:
# the API reference is behind its own automake conditional. The generated
# Makefile shows it plainly --
#
#   @COND_DOXYGEN_TRUE@$(top_builddir)/doc/api/index.html: ...
#
# -- with the prefix stripped, so configure had set it true.
#
# --disable-doxygen is not in configure's help text; only --enable-doxygen is.
# It works anyway, and that was CHECKED rather than assumed: AC_ARG_ENABLE
# always accepts both forms, and `enable_doxygen` is a real variable the script
# tests. groff taught this the other way round -- there, no such option existed
# at all, and an invented flag would have drawn a warning and changed nothing.
lines.insert(i + 1, ind + "  --disable-doc --disable-doxygen \\")
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lines))
ZZPY
grep -A1 -E "^[[:space:]]*\./configure" PKGBUILD | grep -q -- "--disable-doxygen" || {
    echo "xz: --disable-doxygen is not on the configure line" >&2; exit 1; }
echo "xz: man pages and doxygen API reference both disabled"
