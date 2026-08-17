#!/usr/bin/env bash
# pacman: bare meson takes its libdir from the Debian host.
#
# The build host is Ubuntu, so meson's default_libdir() asks
# dpkg-architecture for the multiarch tuple and hands back
#
#   lib/s390x-linux-gnu
#
# devtools' arch-meson would override that, but this PKGBUILD calls BARE
# `meson`, so nothing does. The build then succeeds, makepkg exits 0, and the
# package ships
#
#   usr/lib/s390x-linux-gnu/libalpm.so.16
#
# where Arch's ld.so never looks -- it reads /usr/lib. libalpm is pacman's
# OWN library, so a target installed from this package has a package manager
# that cannot start, and no way to pacman -U the fix. Nothing in the build log
# says a word about it. This is the single most expensive instance of the
# libdir slip in the port, which is why it gets its own hook rather than
# waiting for the arch-meson stand-in to cover it.
#
# The same slip poisons two things downstream of the library file:
#   - .../pkgconfig/libalpm.pc, whose `libdir=${prefix}/lib/s390x-linux-gnu`
#     then aims every consumer at the same dead directory;
#   - makepkg's own autodep. /etc/makepkg.conf sets
#     LIB_DIRS=('lib:usr/lib' 'lib32:usr/lib32') and library_provides.sh runs
#     `find "$pkgdir/$dir" -maxdepth 1`, so it never descends into the
#     multiarch directory. .PKGINFO recorded a bare `provides = libalpm.so`
#     with no version, where it should read libalpm.so=16-64 -- so every
#     `libalpm.so=16-64` dependency in the port would go unsatisfiable, and
#     the error would name the package that wanted it, never pacman.
#
# Only the configure call takes a libdir. The other four `meson` words in the
# file -- makedepends, compile, test, install -- take none and are left alone.
# The count is asserted rather than assumed.
#
# libdir only. sbindir and libexecdir also keep non-Arch defaults here, but
# pacman installs nothing into either -- the manifest is /usr/{bin,include,
# lib,share} and /etc, nothing else. Setting them would be a change with no
# artefact behind it, and if upstream ever does add an sbin binary we want to
# see it rather than have it silently absorbed.
set -euo pipefail
python3 - <<'PY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()
old = "  meson --prefix=/usr \\\n"
n = s.count(old)
assert n == 1, "pacman: expected 1 meson configure call, found %d" % n
assert "libdir" not in s, "pacman: PKGBUILD already sets a libdir, re-read it"
s = s.replace(old, old + "        --libdir=lib \\\n", 1)
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
PY
[ "$(grep -c -- '--libdir=lib' PKGBUILD)" = 1 ] || {
    echo "pacman: libdir not forced to lib exactly once" >&2; exit 1; }
echo "pacman: libdir forced to /usr/lib (Debian host defaults it to multiarch)"
