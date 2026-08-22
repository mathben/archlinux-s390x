#!/usr/bin/env bash
# libxcrypt: build with a compiler newer than it expects.
#
#   lib/crypt-gost-yescrypt.c:134:16: error: initialization discards 'const'
#     qualifier from pointer target type
#
# A warning, promoted to an error by libxcrypt's own -Werror. Our gcc is 16.2.1;
# libxcrypt 4.5.2 was released against considerably older ones, and this
# diagnostic is not about the port -- the same code warns the same way on x86_64
# with the same compiler.
#
# --disable-werror is libxcrypt's own switch. Patching the source would mean
# carrying a diff against upstream C for a const-correctness nit in an
# implementation of a Russian hash standard that nothing here uses; declining to
# treat warnings as errors is what a distribution does when its compiler is
# ahead of a release.
#
# BOTH CONFIGURE CALLS. libxcrypt is built twice -- once normally and once for
# the obsolete-API compat library -- and fixing only the first leaves the second
# failing identically, which reads as if the flag had no effect.
set -euo pipefail
python3 - <<'ZZPY'
import io, re
lines = io.open("PKGBUILD", encoding="utf-8").read().split("\n")
hit = [i for i, l in enumerate(lines) if re.search(r"/configure[ \t]*\\\\?$", l)]
assert len(hit) == 2, "libxcrypt: expected two configure calls, got %d" % len(hit)
# Backwards, so inserting does not move the indices still to be used.
for i in reversed(hit):
    ind = re.match(r"^[ \t]*", lines[i]).group(0)
    assert lines[i].rstrip().endswith("\\"), \
        "libxcrypt: a configure call does not continue: %r" % lines[i]
    lines.insert(i + 1, ind + "  --disable-werror \\")
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lines))
ZZPY
n=$(grep -c -- "--disable-werror" PKGBUILD)
[ "$n" = 2 ] || { echo "libxcrypt: expected 2 --disable-werror, found $n" >&2; exit 1; }
echo "libxcrypt: -Werror disabled in both builds"
