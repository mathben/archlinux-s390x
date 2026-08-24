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

# --- no Rust ------------------------------------------------------------------
#
#   cargo: command not found
#
# git's PKGBUILD passes WITH_RUST=1 and lists rust in makedepends. This port does
# not package Rust, and packaging it is not a package: rustc bootstraps from a
# previous rustc, which is the one thing a from-source distribution cannot start
# from -- Arch ships a binary to break that cycle, and this port has no such
# escape on s390x.
#
# WHY IT SURFACED ONLY NOW. Stage 1 built git happily: the HOST has rustc, from
# apt. So this is another entry in the longest-running theme of the port -- a
# dependency the host satisfied invisibly, appearing the first time the chroot is
# the one being asked. And it appeared only after the man-page section above
# started running at stage 2, which it had not been doing.
#
# WITH_RUST=1 selects Rust reimplementations of some internals; git builds and
# behaves the same without it. Both stages, so the two agree: stage 1 was
# producing a git that stage 2 could not reproduce.
python3 - <<'ZZPY'
import io, re
lines = io.open("PKGBUILD", encoding="utf-8").read().split("\n")
# NO_RUST=1, not merely dropping WITH_RUST=1.
#
# Removing WITH_RUST=1 changed nothing -- cargo was still invoked:
#
#   CARGO target/release/libgitcore.a
#   /bin/sh: line 1: cargo: command not found
#
# The Makefile reads
#
#   ifndef NO_RUST
#   BASIC_CFLAGS += -DWITH_RUST
#   GITLIBS += $(RUST_LIB)
#
# so Rust is built BY DEFAULT and the opt-out is NO_RUST. WITH_RUST=1 in the
# PKGBUILD sets a variable the Makefile never reads; deleting it was correct and
# insufficient, which is the worst combination -- the hook reported success and
# the build failed identically.
#
# Worth recording as an upstream change: git now needs a Rust toolchain unless
# told otherwise. For a distribution bootstrapped from source that is a real
# obstacle, because rustc bootstraps from a previous rustc.
hit = [i for i, l in enumerate(lines) if re.match(r"^[ \t]*WITH_RUST=1[ \t]*$", l)]
assert len(hit) == 1, "git: expected one WITH_RUST=1 line, got %d" % len(hit)
lines[hit[0]] = re.match(r"^[ \t]*", lines[hit[0]]).group(0) + "NO_RUST=1"
out = [l.replace(" 'rust'", "") if "makedepends" in l else l for l in lines]
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(out))
ZZPY
grep -qE "^[[:space:]]*WITH_RUST=1" PKGBUILD && { echo "git: WITH_RUST survived" >&2; exit 1; }
grep -qE "^[[:space:]]*NO_RUST=1" PKGBUILD || { echo "git: NO_RUST=1 was not set" >&2; exit 1; }
grep -q "'rust'" PKGBUILD && { echo "git: rust still in makedepends" >&2; exit 1; }
echo "git: built without Rust (no rustc to bootstrap from on s390x)"

# --- no libsecret credential helper -------------------------------------------
#
#   make: *** [Makefile:20: git-credential-libsecret.o] Error 1
#
# contrib/credential/libsecret needs libsecret's headers, and libsecret is not in
# this port -- it is a GNOME keyring client, and behind it sit glib2 and
# gobject-introspection, the sub-project already declined for p11-kit.
#
# THREE PLACES, and one of them spans two lines:
#
#   52   _make -C contrib/credential/libsecret
#   106  install -m 0755 contrib/credential/libsecret/git-credential-libsecret \
#   107      "$pkgdir"/usr/lib/git-core/git-credential-libsecret
#   108  _make -C contrib/credential/libsecret clean
#
# The first version of this section asserted "expected one _make, got 2" and
# stopped, which is the guard doing its job. Replacing line 106 alone would leave
# 107 as a command of its own -- the binutils continuation trap again, and the
# reason the install is deleted as a range rather than commented.
#
# The optdepend line stays: it describes what the helper would need if someone
# built it, and it is a sentence, not a dependency.
python3 - <<'ZZPY'
import io, re
lines = io.open("PKGBUILD", encoding="utf-8").read().split("\n")

mk = [i for i, l in enumerate(lines)
      if re.search(r"_make -C contrib/credential/libsecret", l)]
assert len(mk) == 2, "git: expected two libsecret _make lines, got %d" % len(mk)

ins = [i for i, l in enumerate(lines)
       if re.match(r"^[ \t]*install ", l) and "credential/libsecret" in l]
assert len(ins) == 1, "git: expected one libsecret install, got %d" % len(ins)
i = ins[0]
j = i
while lines[j].rstrip().endswith("\\"):
    j += 1
# Delete the install and its continuations, then neutralise both _make lines.
# Backwards, so earlier indices stay valid.
for k in reversed(mk):
    ind = re.match(r"^[ \t]*", lines[k]).group(0)
    lines[k] = ind + ": # libsecret is not packaged here (glib2, gobject-introspection)."
del lines[i:j + 1]
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lines))
ZZPY
grep -qE "^[[:space:]]*_make -C contrib/credential/libsecret" PKGBUILD && {
    echo "git: a libsecret build survived" >&2; exit 1; }
grep -qE "^[[:space:]]*install .*credential/libsecret" PKGBUILD && {
    echo "git: the libsecret install survived" >&2; exit 1; }
grep -q "git-credential-libsecret" PKGBUILD && {
    echo "git: a reference to the helper binary survived" >&2; exit 1; }
echo "git: libsecret credential helper dropped"
