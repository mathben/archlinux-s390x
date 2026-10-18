#!/usr/bin/env bash
# "host-tuple" is a placeholder, not a target. Sourced by the hooks that meet
# it; not a hook itself.
#
# Some recipes prefetch their crates with
#
#   cargo fetch --locked --target host-tuple
#
# and cargo reads that word as the name of a target specification, which no
# toolchain defines:
#
#   error: Error loading target specification: Could not find specification
#   for target "host-tuple"
#
# prepare() then fails before anything is compiled. The word stands for the
# triple the compiler was built for, which rustc reports and which is the only
# value that can be right on both a build host and a foreign-architecture
# chroot. Resolving it at build time rather than writing s390x by hand keeps
# the recipe correct wherever it runs.
set -euo pipefail
python3 - <<'ZZPY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()
old = "--target host-tuple"
assert s.count(old) >= 1, "cargo host-tuple: placeholder not found"
new = '--target "$(rustc -vV | sed -n \'s/^host: //p\')"'
s = s.replace(old, new)
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
ZZPY
grep -q "host-tuple" PKGBUILD && {
    echo "cargo host-tuple: the placeholder survives" >&2; exit 1; }
grep -q "rustc -vV" PKGBUILD || {
    echo "cargo host-tuple: the substitution was not written" >&2; exit 1; }
echo "$(basename "$PWD"): cargo target resolved from rustc"
