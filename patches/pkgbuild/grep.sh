#!/usr/bin/env bash
# grep: neutralise the pkg.m4 serial check inside bootstrap.conf.
#
#   ./bootstrap: do not use pkg.m4 serial 12;
#   see https://lists.gnu.org/r/grep-devel/2025-04/msg00006.html
#
# grep is the only package here that INSPECTS the version of the m4 macros
# its build host provides. Not an s390x incompatibility: the same refusal
# happens on any Ubuntu host, x86 included -- pkg-config 0.29.2 ships that
# serial everywhere.
#
# TWO EARLIER VERSIONS OF THIS HOOK WERE WRONG, both for the same reason --
# assuming the shape of a file instead of reading it:
#
#   1. Skipping ./bootstrap. The source is a git checkout, not a released
#      tarball, so that removed configure itself:
#        PKGBUILD: line 43: ./configure: No such file or directory
#   2. Editing `bootstrap`. The check is not there. It lives in
#      bootstrap.conf, in a shell function, built from a $url variable --
#      which is why grepping for the literal message found nothing.
#
# The check is two lines: a grep for the serial, and a die. Replaced by a
# no-op that keeps the surrounding function valid.
set -euo pipefail
python3 - <<'PY'
import io, re
s = io.open("PKGBUILD", encoding="utf-8").read()
fix = """  # Port: bootstrap.conf refuses the host pkg.m4 serial; see
  # patches/pkgbuild/grep.sh. The check spans two lines, ending in "|| :".
  sed -i "/serial 12. m4.pkg.m4/,+1c\\\\  :" bootstrap.conf
"""
m = re.search(r"\nprepare\(\) \{\n(\s*cd [^\n]*\n)", s)
assert m, "prepare() with a cd not found"
s = s[:m.end()] + fix + s[m.end():]
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
PY
grep -q 'bootstrap.conf refuses the host pkg.m4' PKGBUILD || {
    echo "grep: patch step not inserted" >&2; exit 1; }
grep -qE '^\s*\./bootstrap' PKGBUILD || {
    echo "grep: bootstrap no longer invoked -- configure would be missing" >&2; exit 1; }
echo "grep: bootstrap kept, its bootstrap.conf serial check neutralised"
