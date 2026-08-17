#!/usr/bin/env bash
# brotli: two Debian defaults, and both of them ship silently.
#
# Neither produces an error. makepkg exits 0 both times and the repository
# gains a package whose files are in places nothing on the target will look.
# This is the case "an exit code proves nothing, only the artefact proves"
# was written for -- the symptom arrives months later, far from the cause.
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

# 2. The python wheel, and an honest account of what this buys.
#
# package_python-brotli() runs
#
#   python -m installer --destdir="$pkgdir" dist/*.whl
#
# and `installer` asks sysconfig where a wheel belongs. Debian and Ubuntu
# patch sysconfig to prefer the "posix_local" scheme, so the answer here is
# /usr/local/lib/python3.13/dist-packages. Verified by running the real wheel
# through the real installer into a scratch pkgdir.
#
# BE CLEAR ABOUT WHAT THIS FIXES. It does NOT make the module importable on
# Arch. Arch ships python 3.14 and this wheel is cp313 with an ABI-tagged
# _brotli.cpython-313-*.so, so no destination makes a stage-1 wheel work on
# the target; stage 2 is what produces a usable one. What the move buys is
# that an Arch package must not ship files under /usr/local, which Arch
# reserves for the administrator. That is the whole justification, and
# writing a bigger one here would mislead the next reader.
#
# `installer --prefix=/usr` does NOT help: posix_local is literally
# "{base}/local/lib/pythonX.Y/dist-packages", so overriding base with /usr
# still lands in /usr/local. The SCHEME would have to change, and the only
# supported way to change it is to be a different interpreter.
#
# Guarded on the directory, not the host name: under an Arch python the
# directory is absent and the block does nothing. Only purelib moves -- the
# wheel declares py_modules=["brotli"] plus the extension, no scripts and no
# data files, so nothing else of it ever leaves /usr/local.
python3 - <<'PY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()
old = '  python -m installer --destdir="$pkgdir" dist/*.whl\n'
assert old in s, "installer invocation not found"
new = old + """  # Ubuntu's python installs to /usr/local/lib/pythonX.Y/dist-packages
  # (sysconfig's posix_local scheme). An Arch package may not ship /usr/local.
  local _pyver=$(python -c 'import sys; print("%d.%d" % sys.version_info[:2])')
  if [ -d "$pkgdir/usr/local/lib/python$_pyver/dist-packages" ]; then
    install -dm 755 "$pkgdir/usr/lib/python$_pyver"
    mv "$pkgdir/usr/local/lib/python$_pyver/dist-packages" \\
       "$pkgdir/usr/lib/python$_pyver/site-packages"
    rm -rf "$pkgdir/usr/local"
  fi
"""
s = s.replace(old, new, 1)
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
PY
grep -q "posix_local scheme" PKGBUILD || {
    echo "brotli: wheel relocation not inserted" >&2; exit 1; }
echo "brotli: python wheel moved out of /usr/local"
