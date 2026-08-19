#!/usr/bin/env bash
# libgcrypt: the first package the host is too OLD for, rather than missing
# something.
#
#   configure: Use gpgrt-config with /usr/lib/s390x-linux-gnu as gpg-error-config
#   checking for GPG Error - version >= 1.56... no
#   configure: error: libgpg-error is needed.
#
# libgcrypt 1.12.2 wants libgpg-error >= 1.56. Ubuntu ships 1.51. Installing a
# -dev package cannot fix a version floor, and every earlier failure in this
# port was an absence -- this one is an age.
#
# THE TRAP is the first line. configure DID find gpgrt-config and DID pick a
# libdir, so the message reads like a path problem and sends you checking
# multiarch directories. The path was right all along; only the version was
# wrong. config.log is where it says so, four lines further down, and the
# summary on stderr never mentions a version at all.
#
# WE ALREADY BUILT WHAT IS NEEDED. repo/s390x holds libgpg-error 1.61,
# complete with usr/bin/gpgrt-config and usr/lib/pkgconfig/gpg-error.pc.
#
# SO THIS HOOK CROSSES A LINE, DELIBERATELY, AND IT IS WORTH NAMING. Stage 1
# builds against the HOST's libraries; consuming stage 1's own output is the
# property that defines stage 2. Here the host cannot supply a new enough
# library at all, so the choice was between using our own package and
# deferring libgcrypt -- which gnupg and systemd both declare, so the
# repository would not resolve. Using our own is also what a bootstrap does:
# each package built becomes an input available to the next. And stage 2
# rebuilds everything inside the chroot regardless, so this host-versus-ours
# distinction is erased there rather than inherited.
#
# Expect the precedent to recur at the next version floor.
#
# HOW, rather than --with-libgpg-error-prefix. That flag looks like the
# answer and is not: it sets GPG_ERROR_CONFIG to "$prefix/bin/gpg-error-config",
# a program modern libgpg-error no longer ships -- 1.61 has only gpgrt-config,
# invoked as `gpgrt-config gpg-error ...`. Pointing the flag at our prefix
# would name a file that does not exist, configure would fall back to the PATH
# and find the host's 1.51 again, and the error would not move.
#
# GPGRT_CONFIG is the variable configure actually consults. From its location
# it derives a prefix, then looks for pkgconfig/gpg-error.pc under
# <prefix>/lib -- which our extracted tree has. Verified by running the real
# configure on a copy:
#
#   checking for gpgrt-config... .../stage1-prefix/usr/bin/gpgrt-config
#   configure: Use gpgrt-config with .../stage1-prefix/usr/lib as gpg-error-config
#   checking for GPG Error - version >= 1.56... yes (1.61-unknown)
#   configure rc=0
#
# The export goes INTO build(). This hook runs in its own bash process, so an
# export here would never reach makepkg -- the same reason gcc.sh puts its
# MAKEFLAGS bound inside build() rather than at hook level.
set -euo pipefail

WORK="${WORK:-$HOME/work/arch-s390x}"
PREFIX="$WORK/stage1-prefix"

# Refreshed on every run rather than cached: if libgpg-error is rebuilt, a
# stale prefix would silently keep feeding the old one -- the same class of
# invisible staleness as the arch-meson copy left in /usr/local.
shopt -s nullglob
_gpe=("$WORK"/repo/s390x/libgpg-error-*.pkg.tar.*)
shopt -u nullglob
[ "${#_gpe[@]}" -ge 1 ] || {
    echo "libgcrypt: no libgpg-error package in $WORK/repo/s390x" >&2; exit 1; }
rm -rf "$PREFIX"
mkdir -p "$PREFIX"
bsdtar -xf "${_gpe[0]}" -C "$PREFIX" usr || {
    echo "libgcrypt: could not extract ${_gpe[0]}" >&2; exit 1; }
[ -x "$PREFIX/usr/bin/gpgrt-config" ] || {
    echo "libgcrypt: extracted prefix has no gpgrt-config" >&2; exit 1; }
[ -f "$PREFIX/usr/lib/pkgconfig/gpg-error.pc" ] || {
    echo "libgcrypt: extracted prefix has no gpg-error.pc" >&2; exit 1; }
_ver=$("$PREFIX/usr/bin/gpgrt-config" gpg-error --version 2>/dev/null || true)
echo "libgcrypt: stage-1 prefix holds libgpg-error ${_ver:-unknown}"

PREFIX="$PREFIX" python3 - <<'PY'
import io, os
s = io.open("PKGBUILD", encoding="utf-8").read()
assert "GPGRT_CONFIG" not in s, "libgcrypt: GPGRT_CONFIG already set, hook ran twice"
anchor = "build() {\n"
assert s.count(anchor) == 1, "libgcrypt: expected exactly one build()"
prefix = os.environ.get("PREFIX")
inject = anchor + (
    "  # Our own libgpg-error 1.61: the host's 1.51 is below the 1.56 floor.\n"
    "  export GPGRT_CONFIG=%s/usr/bin/gpgrt-config\n" % prefix)
s = s.replace(anchor, inject, 1)
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
PY
grep -q "export GPGRT_CONFIG=$PREFIX/usr/bin/gpgrt-config" PKGBUILD || {
    echo "libgcrypt: GPGRT_CONFIG not injected into build()" >&2; exit 1; }
echo "libgcrypt: build() points at our gpgrt-config (host libgpg-error is 1.51)"
