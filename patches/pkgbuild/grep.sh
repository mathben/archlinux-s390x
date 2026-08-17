#!/usr/bin/env bash
# grep: neutralise the pkg.m4 serial check inside its own bootstrap script.
#
#   ./bootstrap: do not use pkg.m4 serial 12;
#   see https://lists.gnu.org/r/grep-devel/2025-04/msg00006.html
#
# grep is the only package here that INSPECTS the version of the m4 macros
# its build host provides. This is not an s390x incompatibility: the same
# refusal happens on any Ubuntu host, x86 included.
#
# A PREVIOUS VERSION of this hook skipped ./bootstrap entirely, on the
# assumption that the source was a released tarball and therefore already
# bootstrapped. It is not -- it is a git checkout, so skipping bootstrap
# removed configure itself:
#
#   PKGBUILD: line 43: ./configure: No such file or directory
#
# The check itself is what has to go, and it lives in the extracted source,
# so it is removed from prepare() rather than from the PKGBUILD directly.
set -euo pipefail
python3 - <<'PY'
import io, re
s = io.open("PKGBUILD", encoding="utf-8").read()
fix = """  # Port: drop bootstrap's host m4 vetting; see patches/pkgbuild/grep.sh
  sed -i '/do not use pkg.m4 serial/,+1d' bootstrap
"""
m = re.search(r"\nprepare\(\) \{\n(\s*cd [^\n]*\n)", s)
assert m, "prepare() with a cd not found"
s = s[:m.end()] + fix + s[m.end():]
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
PY
grep -q "drop bootstrap's host m4 vetting" PKGBUILD || {
    echo "grep: m4 check removal not inserted" >&2; exit 1; }
grep -qE '^\s*\./bootstrap' PKGBUILD || {
    echo "grep: bootstrap is no longer invoked -- configure would be missing" >&2; exit 1; }
echo "grep: bootstrap kept, its pkg.m4 serial check neutralised"
