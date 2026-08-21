#!/usr/bin/env bash
# ca-certificates: no man page for update-ca-trust.
#
#   a2x: command not found
#
# a2x belongs to asciidoc, a Python toolchain whose only job here is turning
# update-ca-trust.8.txt into update-ca-trust.8. TWO lines have to go, not one:
# build() renders it and package() installs it. Removing only the render leaves
#
#   install: cannot stat 'update-ca-trust.8'
#
# which is the same shape as libxml2's docs split -- a failure on the last line
# of package(), naming a path, after a build that worked.
set -euo pipefail
python3 - <<'ZZPY'
import io, re
lines = io.open("PKGBUILD", encoding="utf-8").read().split("\n")
a2x = [i for i, l in enumerate(lines) if re.match(r"^[ \t]*a2x\b", l)]
man = [i for i, l in enumerate(lines) if "update-ca-trust.8" in l and "install " in l]
assert len(a2x) == 1, "ca-certificates: expected one a2x call, got %d" % len(a2x)
assert len(man) == 1, "ca-certificates: expected one man install, got %d" % len(man)
lines[a2x[0]] = "  # a2x removed: no asciidoc toolchain at either stage."
lines[man[0]] = "  # man page not installed: nothing rendered it."
out = [l.replace("  asciidoc\n", "") for l in lines]
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(out))
ZZPY
grep -q "a2x removed" PKGBUILD && grep -q "nothing rendered it" PKGBUILD || {
    echo "ca-certificates: one of the two lines was not replaced" >&2; exit 1; }
echo "ca-certificates: update-ca-trust man page dropped"
