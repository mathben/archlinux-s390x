#!/usr/bin/env bash
# expat: bare cmake picks up the Debian multiarch libdir.
#
# The PKGBUILD calls cmake directly -- NOT arch-cmake -- so the devtools
# stand-in that already passes -DCMAKE_INSTALL_LIBDIR=lib never runs. The
# option array only pins the prefix.
#
# expat's CMakeLists include(GNUInstallDirs), and GNUInstallDirs picks its
# default LIBDIR by sniffing the HOST: it sees /etc/debian_version, finds no
# /etc/arch-release, and sets lib/<multiarch> = lib/s390x-linux-gnu. Because
# CMAKE_INSTALL_LIBDIR was never given, that default wins and is cached.
#
# The build then exits 0 and the package installs cleanly. It is the ARTEFACT
# that is wrong -- everything LIBDIR-derived lands off Arch's search paths:
#
#   usr/lib/s390x-linux-gnu/libexpat.so.1.12.3   ld.so reads /usr/lib only
#   usr/lib/s390x-linux-gnu/pkgconfig/expat.pc   pkgconf reads /usr/lib only
#   usr/lib/s390x-linux-gnu/cmake/expat-2.8.3/   find_package(EXPAT) misses
#
# and usr/lib itself holds nothing but that subdirectory. expat is a
# dependency of cmake, python, gdb and fontconfig, so this does not fail
# loudly here -- it fails later, in whatever links against -lexpat.
#
# The fix is to state the libdir the stand-in would have stated. Passing it on
# the command line makes it a cache entry BEFORE GNUInstallDirs runs, and
# GNUInstallDirs only fills in defaults for variables that are still unset.
#
# One configure call, so exactly one insertion: assert the count rather than
# rewriting every -D.
set -euo pipefail
python3 - <<'PY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()
assert "CMAKE_INSTALL_LIBDIR" not in s, "expat: libdir already set, hook ran twice"
anchor = "    -D CMAKE_INSTALL_PREFIX=/usr\n"
n = s.count(anchor)
assert n == 1, "expat: expected 1 cmake option block, found %d" % n
s = s.replace(anchor, anchor + "    -D CMAKE_INSTALL_LIBDIR=lib\n", 1)
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
PY
[ "$(grep -c 'CMAKE_INSTALL_LIBDIR=lib' PKGBUILD)" = 1 ] || {
    echo "expat: libdir not pinned exactly once" >&2; exit 1; }
echo "expat: CMAKE_INSTALL_LIBDIR=lib (bare cmake bypasses arch-cmake)"
