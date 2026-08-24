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
# A PROBE, not a constant, and it runs in the BUILD ENVIRONMENT.
#
# The first version set _bootstrap=1 unconditionally. That is right on a machine
# with no Python packaging stack and wrong the moment there is one, because the
# vendored builder carries its OWN copy of each project -- older than the
# PKGBUILD's pkgver. python-packaging was labelled 26.3 and installed 25.0, and
# the mismatch surfaced two packages later:
#
#   python-vcs-versioning: packaging>=26.2
#
# a floor our own package met on paper and not in fact. Nothing about the
# installed package looked wrong; only `import packaging; packaging.__version__`
# disagreed with its name.
#
# So the PKGBUILD decides at build time, where the answer is knowable: if `build`
# and `installer` import, the real path works and the vendored copies are not
# wanted. Hooks run on the HOST even for stage 2, so a probe written here could
# not answer for the chroot -- this one is evaluated by makepkg, inside it.
python3 - <<'ZZPY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()
old = "_bootstrap=0"
assert s.count(old) == 1, "python bootstrap: expected one _bootstrap=0, got %d" % s.count(old)
new = ("# Bootstrap only when the real path is unavailable -- see\n"
       "# patches/pkgbuild/lib-python-bootstrap.sh. Evaluated by makepkg, in the\n"
       "# build environment, because that is where the answer lives.\n"
       "_bootstrap=1\n"
       "python -c 'import build, installer' >/dev/null 2>&1 && _bootstrap=0")
s = s.replace(old, new, 1)
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
ZZPY
grep -q "^_bootstrap=1$" PKGBUILD || {
    echo "python bootstrap: the default was not set to 1" >&2; exit 1; }
grep -q "import build, installer" PKGBUILD || {
    echo "python bootstrap: the probe was not inserted" >&2; exit 1; }
# The branch it selects must actually exist, or the switch silently builds
# nothing -- these PKGBUILDs are not required to have both halves.
grep -q "bootstrap.build" PKGBUILD || {
    echo "python bootstrap: no bootstrap.build branch in this PKGBUILD" >&2; exit 1; }
echo "$(basename "$PWD"): _bootstrap=1 (Arch's vendored builder)"
