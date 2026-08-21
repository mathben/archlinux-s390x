#!/usr/bin/env bash
# Arch's own escape hatch for the Python packaging cycle. Sourced by the six
# hooks that need it; not a hook itself.
#
# THE CYCLE. Three stage-2 builds -- brotli, libseccomp, meson -- stopped on
#
#   /usr/bin/python: No module named build
#
# and building python-build means running `python -m build`, which is
# python-build. Its dependencies are the same: packaging and pyproject-hooks are
# flit_core-backed, installing a wheel wants python-installer, and none of them
# exist yet.
#
# On the host the cycle was already broken -- apt had python3-build -- so stage 1
# never met it. Trying to break it there again failed for a reason worth
# recording: `apt-cache policy python3-flit-core` returns no candidate at all.
# Ubuntu does not package it, so the backend every one of these needs cannot be
# installed on the host by any means. Our own python-flit-core builds fine, but
# building a package is not installing it.
#
# ARCH ALREADY SOLVED THIS, and the solution is in the PKGBUILDs:
#
#   if (( _bootstrap == 0 )); then
#     python -m build -wn --skip-dependency-check
#   else
#     cd python-bootstrap
#     python -m bootstrap.build
#   fi
#
# python-bootstrap is a vendored builder that needs none of the six. Setting
# _bootstrap=1 is upstream's supported path through exactly this situation --
# far better than the alternative that was half-written here first, which was a
# per-package hook calling `python -m flit_core.wheel` and unzipping the result
# into $pkgdir by hand. That would have been three bespoke reimplementations of
# something the PKGBUILD already does properly.
#
# It also means these build on the HOST, where they had failed, so they need no
# stage-2 special handling at all.
set -euo pipefail
python3 - <<'ZZPY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()
old = "_bootstrap=0"
assert s.count(old) == 1, "python bootstrap: expected one _bootstrap=0, got %d" % s.count(old)
s = s.replace(old, "_bootstrap=1  # see patches/pkgbuild/lib-python-bootstrap.sh", 1)
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
ZZPY
grep -q "^_bootstrap=1" PKGBUILD || {
    echo "python bootstrap: _bootstrap was not switched" >&2; exit 1; }
# The branch it selects must actually exist, or the switch silently builds
# nothing -- these PKGBUILDs are not required to have both halves.
grep -q "bootstrap.build" PKGBUILD || {
    echo "python bootstrap: no bootstrap.build branch in this PKGBUILD" >&2; exit 1; }
echo "$(basename "$PWD"): _bootstrap=1 (Arch's vendored builder)"
