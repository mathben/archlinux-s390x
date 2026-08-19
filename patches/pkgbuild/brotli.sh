#!/usr/bin/env bash
# brotli: a Debian default that ships silently, and a sub-package that costs
# more than it is worth.
#
# The first produces no error. makepkg exits 0 and the repository gains a
# package whose library sits where nothing on the target will look -- the case
# "an exit code proves nothing, only the artefact proves" was written for,
# where the symptom arrives months later, far from the cause.
#
# The second is a closure decision, not a defect, and it is measured rather
# than argued.
set -euo pipefail

# 1. The C library, and the one that actually matters.
#
# brotli's PKGBUILD calls plain `cmake`, not the arch-cmake stand-in, so it
# never sees the -DCMAKE_INSTALL_LIBDIR=lib that stand-in passes. CMake's
# GNUInstallDirs then picks its branch by sniffing the host: no
# /etc/arch-release, /etc/debian_version present, so
#
#   CMAKE_INSTALL_LIBDIR = lib/s390x-linux-gnu
#
# Measured on a DESTDIR install of a real build: libbrotlicommon.so.1,
# libbrotlidec.so.1, libbrotlienc.so.1 and their .pc files all under
# /usr/lib/s390x-linux-gnu. brotli is in stage 1 only because the chroot said
# openssl and curl need libbrotli*.so -- and the filesystem package's
# /etc/ld.so.conf reads only ld.so.conf.d, so the target would never find
# them. A no-op in stage 2, where CMake takes the /etc/arch-release branch.
python3 - <<'PY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()
old = '    -DCMAKE_INSTALL_PREFIX=/usr \\\n'
assert s.count(old) == 1, "expected exactly one cmake configure, found %d" % s.count(old)
s = s.replace(old, old + '    -DCMAKE_INSTALL_LIBDIR=lib \\\n', 1)
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
PY
grep -q 'DCMAKE_INSTALL_LIBDIR=lib' PKGBUILD || {
    echo "brotli: libdir not pinned" >&2; exit 1; }
echo "brotli: cmake libdir pinned to lib (host GNUInstallDirs says multiarch)"

# 2. python-brotli: dropped, because it costs the entire python closure.
#
# THE MEASUREMENT THAT DECIDED IT. pacman resolver named 70 missing
# dependencies. Excluding this one sub-package from the ledger took that to
# 47 and removed `python` outright -- with libffi, mpdecimal and gdbm behind
# it. Three packages of closure, for one module.
#
# And the module could not work anyway. The wheel is built by the host python
# 3.13 and is ABI-tagged cpython-313; Arch ships 3.14. No destination makes it
# importable on the target, so stage 2 is what has to produce a real one.
# TODO.md carries that entry already.
#
# Note what is NOT the reason. The wheel also lands in
# /usr/local/lib/python3.13/dist-packages, because Debian patches sysconfig to
# prefer its posix_local scheme, and an Arch package may not ship /usr/local.
# That was worth a relocation while the sub-package existed; with the
# sub-package gone there is nothing to relocate, and keeping the relocation
# would be editing a package() function makepkg never calls.
#
# build() still builds the wheel -- it is one function for all three
# sub-packages -- and the result is simply not packaged. Cheap, and it keeps
# this hook to one line of real change.
#
# brotli-testdata stays: nothing depends on it, it costs no closure, and
# removing it would be churn.
python3 - <<'PYB'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()
old = "pkgname=('brotli' 'python-brotli' 'brotli-testdata')"
assert s.count(old) == 1, "brotli: expected exactly one pkgname line"
s = s.replace(old, "pkgname=('brotli' 'brotli-testdata')", 1)
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
PYB
grep -q "^pkgname=('brotli' 'brotli-testdata')$" PKGBUILD || {
    echo "brotli: python-brotli not removed from pkgname" >&2; exit 1; }
grep -q "python-brotli" PKGBUILD &&     echo "brotli: python-brotli remains only in its own package function (never called)"
echo "brotli: python-brotli dropped (pulled the whole python closure)"
