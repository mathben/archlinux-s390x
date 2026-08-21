#!/usr/bin/env bash
# filesystem: s390x gets the lib64 compatibility symlinks too.
#
# Arch's PKGBUILD creates them for one architecture only:
#
#   [[ $CARCH = 'x86_64' ]] && {
#       symlinks["lib64"]="usr/lib"
#       symlinks["usr/lib64"]="lib"
#   }
#
# which is correct for Arch, and wrong here in a way that took five steps to
# see. s390x's toolchain has a 64-bit multi-os subdirectory: gcc reports
# `../lib64` for -print-multi-os-directory, and libiberty's install target uses
# $(libdir)$(MULTIOSSUBDIR). With no symlink, that CREATES /usr/lib64 as a real
# directory -- one static library, from binutils.
#
# From there:
#   meson picks its default libdir with `isdir('/usr/lib64') and not
#   islink(...)`, so a real directory flips every meson package to lib64. pkgconf
#   is a meson package: it installed there and compiled in /usr/lib64/pkgconfig
#   as its search path, while every .pc in the distribution is in
#   /usr/lib/pkgconfig. Every pkg-config lookup in the chroot then failed, and
#   libxslt reported it as
#
#     configure: error: Package requirements (python-3.14) were not met
#
#   with the package installed and its .pc file present.
#
# WITH the symlink, /usr/lib/../lib64 resolves to /usr/lib, so libiberty lands
# where it belongs and meson's test sees a link. One fix at the root instead of
# one per build system -- and it is Arch's own model, not an invention: a single
# library directory with lib64 as compatibility. Ubuntu s390x has no /usr/lib64
# at all, which is why the host never showed any of this.
set -euo pipefail
python3 - <<'ZZPY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()
old = "  [[ $CARCH = 'x86_64' ]] && {"
assert s.count(old) == 1, "filesystem: the x86_64 lib64 guard is not in the expected form"
new = ("  # s390x added: its toolchain installs into $(libdir)/../lib64, which\n"
       "  # creates a REAL /usr/lib64 when no symlink is there -- and that flips\n"
       "  # meson's and other build systems' default libdir.\n"
       "  [[ $CARCH = 'x86_64' || $CARCH = 's390x' ]] && {")
s = s.replace(old, new, 1)
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
ZZPY
grep -q "CARCH = 's390x'" PKGBUILD || { echo "filesystem: s390x not added to the guard" >&2; exit 1; }
# The two symlinks must still be inside the block that was just widened.
grep -A4 "CARCH = 's390x'" PKGBUILD | grep -q 'usr/lib64' || {
    echo "filesystem: the guard was widened but the symlinks are elsewhere" >&2; exit 1; }
echo "filesystem: lib64 -> usr/lib and usr/lib64 -> lib now created on s390x"
