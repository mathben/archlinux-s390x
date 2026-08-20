#!/usr/bin/env bash
# meson: `python -m installer` puts it under /usr/local.
#
#   error: failed to commit transaction (conflicting files)
#   /usr/local/share/man exists in both 'filesystem' and 'meson'
#
# Debian and Ubuntu patch sysconfig to prefer the "posix_local" scheme, so the
# host's python installs a wheel into /usr/local/lib/pythonX.Y/dist-packages
# with its scripts in /usr/local/bin. An Arch package may not ship /usr/local
# at all -- the filesystem package owns that tree, and ships
# usr/local/share/man as a SYMLINK, which is what the conflict is about: our
# meson shipped a directory where filesystem ships a link.
#
# THIRD INSTANCE of this scheme. python-brotli and python-libseccomp were
# simply dropped, because their wheels could not work on the target anyway.
# meson cannot be dropped -- stage 2 needs it to rebuild ten packages -- so it
# gets relocated instead.
#
# STAGE-1 ONLY, and listed in build-stage2.sh's STAGE2_SKIP_HOOKS. Inside the
# chroot the python doing the installing is OUR python, built from Arch's
# PKGBUILD, whose sysconfig answers /usr/lib/pythonX.Y/site-packages without
# being asked. The condition disappears, like git's missing zlib-ng headers and
# libgcrypt's too-old libgpg-error.
#
# AND THE VERSION IS THE TARGET'S, NOT THE HOST'S. This is the part that took
# a failed stage-2 build to see. meson is pure Python, so its ABI does not
# matter -- but the directory NAME carries a version, and the two pythons
# disagree:
#
#   host python      3.13  ->  /usr/lib/python3.13/site-packages
#   our python pkg   3.14  ->  /usr/lib/python3.14/site-packages
#
# Installed under the host's version, /usr/bin/meson runs in the chroot and
# then says
#
#   ModuleNotFoundError: No module named 'mesonbuild'
#
# because the chroot's python -- ours -- never looks in 3.13. So the hook reads
# the version out of the python PACKAGE in repo/s390x, which is the python that
# will actually import this. Deriving it from the interpreter running the build
# is the intuitive thing and the wrong one.
set -euo pipefail
python3 - <<'ZZPY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()
old = '  python -m installer --destdir="$pkgdir" dist/*.whl\n'
assert s.count(old) == 1, "meson: installer invocation not in the expected form"
new = old + """  # Debian's posix_local scheme installs to /usr/local; Arch reserves that
  # tree for the administrator and its filesystem package owns every path in
  # it. Move what the wheel put there, then take the tree away.
  local _repo="${REPO:-$HOME/work/arch-s390x/repo/s390x}"
  # Two layouts to catch. build_package exports
  # DEB_PYTHON_INSTALL_LAYOUT=deb_system, which keeps the wheel out of
  # /usr/local -- but leaves it in dist-packages, which Arch's python does not
  # read. The /usr/local branch stays for anyone running makepkg by hand
  # without that variable.
  # The TARGET python's version, read from our own package -- see the note at
  # the top of this hook. Falls back to the host's only if the package is not
  # built yet, which would be a stage-1 ordering error worth noticing.
  local _pyver
  _pyver=$(bsdtar -xOf "$_repo"/python-[0-9]*.pkg.tar.* .PKGINFO 2>/dev/null \
           | sed -n 's/^pkgver = \\([0-9]*\\.[0-9]*\\).*/\\1/p' | head -1)
  if [ -z "$_pyver" ]; then
    _pyver=$(python -c 'import sys; print("%d.%d" % sys.version_info[:2])')
    echo "  warning: no python package in $_repo, using host python $_pyver" >&2
  fi
  local _site="$pkgdir/usr/lib/python$_pyver/site-packages"
  if [ -d "$pkgdir/usr/local" ]; then
    install -dm 755 "$pkgdir/usr/lib/python$_pyver" "$pkgdir/usr/bin"
    [ -d "$pkgdir/usr/local/lib/python$_pyver/dist-packages" ] && \\
      mv "$pkgdir/usr/local/lib/python$_pyver/dist-packages" "$_site"
    [ -d "$pkgdir/usr/local/bin" ] && mv "$pkgdir/usr/local/bin/"* "$pkgdir/usr/bin/"
    rm -rf "$pkgdir/usr/local"
  fi
  if [ -d "$pkgdir/usr/lib/python3/dist-packages" ]; then
    install -dm 755 "$pkgdir/usr/lib/python$_pyver"
    if [ -d "$_site" ]; then
      cp -a "$pkgdir/usr/lib/python3/dist-packages/." "$_site/"
      rm -rf "$pkgdir/usr/lib/python3/dist-packages"
    else
      mv "$pkgdir/usr/lib/python3/dist-packages" "$_site"
    fi
    rmdir --ignore-fail-on-non-empty "$pkgdir/usr/lib/python3" 2>/dev/null || true
  fi
"""
s = s.replace(old, new, 1)
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
ZZPY
grep -q 'posix_local scheme installs' PKGBUILD || {
    echo "meson: the relocation was not inserted" >&2; exit 1; }
echo "meson: wheel relocated out of /usr/local; STAGE-1 ONLY"
