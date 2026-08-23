#!/usr/bin/env bash
# git: ZLIB_NG=1, and Ubuntu ships no zlib-ng headers.
#
#   compat/zlib-compat.h:5:11: fatal error: zlib-ng.h: No such file or directory
#
# Arch's git links zlib-ng rather than zlib. There is no zlib-ng development
# package on Ubuntu at all -- libz-ng-dev, zlib-ng-dev and libzlib-ng-dev all
# have no candidate -- so the header cannot be had from the host.
#
# THIS HOOK IS STAGE-1 ONLY, and that is the interesting part. Our own zlib-ng
# package DOES ship usr/include/zlib-ng.h, so inside the stage-2 chroot the
# header is present and ZLIB_NG=1 is correct. The hook exists purely because
# stage 1 builds against the host. It is listed in build-stage2.sh's
# STAGE2_SKIP_HOOKS beside libgcrypt.sh, for the same reason: the condition it
# works around does not exist there.
#
# The declaration goes with the flag. git declares zlib-ng in depends, and a
# git built against plain zlib does not use it -- the seventh instance in this
# port of a package asking for something it never linked. `zlib` replaces it,
# which is what the binary will actually need.
#
# WITH_RUST=1 is left alone. rustc and cargo happen to be on this host, so it
# builds -- but the chroot has neither, so stage 2 will stop here and the
# choice will have to be made then: build Rust, or drop the flag. Recorded now
# rather than discovered twice.
set -euo pipefail
# STAGE 1 ONLY -- this section, not this file.
#
# It used to be expressed by naming this hook in STAGE2_SKIP_HOOKS, which skips
# the whole FILE. Then a section was appended that both stages need, and it
# silently never ran: the package kept failing in stage 2 on the very thing the
# new section fixes, and the log said "hook skipped (stage-1 only)" about a hook
# that was now two thirds relevant.
#
# The scope belongs next to the reason, so each section decides for itself.
if [ "${EL_STAGE:-1}" = 1 ]; then

python3 - <<'PY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()

old = "    ZLIB_NG=1\n"
assert s.count(old) == 1, "git: expected exactly one ZLIB_NG=1"
s = s.replace(old, "", 1)

old = "'grep' 'shadow' 'zlib-ng')"
assert s.count(old) == 1, "git: depends tail not in the expected form"
s = s.replace(old, "'grep' 'shadow' 'zlib')", 1)

io.open("PKGBUILD", "w", encoding="utf-8").write(s)
PY
grep -q 'ZLIB_NG' PKGBUILD && {
    echo "git: ZLIB_NG survived" >&2; exit 1; }
grep -q "'zlib-ng'" PKGBUILD && {
    echo "git: zlib-ng still declared" >&2; exit 1; }
grep -qF "'grep' 'shadow' 'zlib')" PKGBUILD || {
    echo "git: zlib not substituted in depends" >&2; exit 1; }
echo "git: plain zlib (no zlib-ng headers on the host); STAGE-1 ONLY"
else
    echo "git: zlib-ng available in the chroot; keeping Arch's choice"
fi

# --- no man pages -------------------------------------------------------------
#
#   asciidoc: command not found
#
# git's man pages come from asciidoc and xmlto, the Python documentation stack
# this port has declined four times now. FOUR PLACES, which is what makes this
# worth a comment: `man` appears as a make target twice and `install-man` twice,
# once each for git proper and once each for contrib/subtree. Removing the build
# targets and leaving the install targets gives
#
#   make: *** No rule to make target 'install-man'
#
# which reads like a broken Makefile.
set -euo pipefail
python3 - <<'ZZPY'
import io, re
lines = io.open("PKGBUILD", encoding="utf-8").read().split("\n")
b = [i for i, l in enumerate(lines) if re.search(r"_make .*\ball man\b", l)]
i2 = [i for i, l in enumerate(lines) if re.search(r"\binstall install-man\b", l)]
assert len(b) == 2, "git: expected two `all man` targets, got %d" % len(b)
assert len(i2) == 2, "git: expected two `install install-man` targets, got %d" % len(i2)
for i in b:
    lines[i] = re.sub(r"\ball man\b", "all", lines[i])
for i in i2:
    lines[i] = re.sub(r"\binstall install-man\b", "install", lines[i])
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lines))
ZZPY
grep -qE "\ball man\b|\binstall-man\b" PKGBUILD && {
    echo "git: a man target survived" >&2; exit 1; }
echo "git: man pages dropped (no asciidoc, four places)"
