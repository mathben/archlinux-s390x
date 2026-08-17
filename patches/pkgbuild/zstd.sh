#!/usr/bin/env bash
# zstd: bare cmake, so nobody passes -DCMAKE_INSTALL_LIBDIR.
#
# This PKGBUILD calls plain `cmake`, not the arch-cmake stand-in, so the
# -DCMAKE_INSTALL_LIBDIR=lib that stand-in supplies never arrives. zstd's own
# build/cmake/CMakeLists.txt does include(GNUInstallDirs), and GNUInstallDirs
# on this build host walks into its Debian branch:
#
#   elseif (EXISTS "/etc/arch-release")   <- absent here
#   elseif (EXISTS "/etc/debian_version") <- present here
#
# and sets CMAKE_INSTALL_LIBDIR=lib/s390x-linux-gnu. The build then exits 0
# and ships the library where Arch's ld.so and pkgconf will never look:
#
#   usr/lib/s390x-linux-gnu/libzstd.so.1.5.7
#   usr/lib/                              <- empty
#
# Note what is NOT the trap here. zstd looks like it might also run a plain
# `make` next to the cmake tree; it does not. There is exactly one configure
# (`cmake -S build/cmake -B build`), `cmake --build build` drives that same
# build dir, and `cmake --install build` installs from it. One insertion
# covers the whole package.
#
# It has to, because CMAKE_INSTALL_LIBDIR is the single root of four separate
# poisoned paths -- fixing only the .so would have left three:
#
#   lib/CMakeLists.txt:279  LIBRARY DESTINATION   -> libzstd.so*
#   lib/CMakeLists.txt:270  pkgconfig             -> libzstd.pc location
#   lib/CMakeLists.txt:264  join_paths(LIBDIR)    -> libdir= INSIDE libzstd.pc
#   CMakeLists.txt:212      ConfigPackageLocation -> cmake/zstd/*.cmake
#
# The third is why this package is worse than it looks. The shipped
# libzstd.pc reads libdir=${exec_prefix}/lib/s390x-linux-gnu, so the poison
# does not stop at zstd: every downstream package that finds zstd through
# pkg-config inherits -L/usr/lib/s390x-linux-gnu and hardcodes a path that
# does not exist on the target. And zstd is a pacman dependency -- pacman
# links libzstd.so.1 -- so the current artefact yields a system that cannot
# run its own package manager to repair itself.
set -euo pipefail
python3 - <<'PY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()
assert "CMAKE_INSTALL_LIBDIR" not in s, "zstd: libdir already pinned, hook ran twice"
old = "    -DCMAKE_INSTALL_PREFIX=/usr \\\n"
n = s.count(old)
assert n == 1, "zstd: expected 1 cmake configure, found %d" % n
s = s.replace(old, old + "    -DCMAKE_INSTALL_LIBDIR=lib \\\n", 1)
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
PY
[ "$(grep -c -- '-DCMAKE_INSTALL_LIBDIR=lib' PKGBUILD)" = 1 ] || {
    echo "zstd: libdir not pinned exactly once" >&2; exit 1; }
echo "zstd: CMAKE_INSTALL_LIBDIR=lib (GNUInstallDirs would say multiarch)"
