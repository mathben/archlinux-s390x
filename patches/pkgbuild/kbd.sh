#!/usr/bin/env bash
# kbd: --disable-xkb. Found by nothing except the artefact.
#
#   $ readelf -d usr/bin/loadkeys | grep NEEDED
#     (NEEDED) Shared library: [libxkbcommon.so.0]
#
#   $ bsdtar -xOf kbd-*.pkg.tar.gz .PKGINFO | grep depend
#     depend = glibc
#     depend = gzip
#     depend = pam
#
# THE POINT OF THIS HOOK IS THE GAP BETWEEN THOSE TWO OUTPUTS. loadkeys needs
# a library the package does not declare, so pacman's resolver is satisfied,
# the rootfs installs cleanly, and loadkeys does not start. No dependency
# check can see this -- not pacman's, and not the closure computation in this
# port, because both read declarations. Only reading the binaries finds it.
# scripts/test-chroot.sh grew a fourth check for exactly this class.
#
# WHERE IT CAME FROM, and it is worth admitting plainly: configure.ac:362
#
#   AC_ARG_ENABLE([xkb], ... [default=auto])
#   AS_IF([test "x$USE_XKB" != xno],
#         [PKG_CHECK_MODULES(XKBCOMMON, xkbcommon, [USE_XKB=yes], [USE_XKB=no])])
#
# 'auto' again -- a default read from the build host. libxkbcommon-dev is on
# this machine because it was added to install_host_deps FOR SYSTEMD. kbd, an
# unrelated package built later, probed for it, found it, and silently linked
# a library nothing in this port ships. One host package, one broken binary in
# a different package, undeclared.
#
# Arch's kbd declares neither libxkbcommon in depends nor in makedepends, so
# Arch's build chroot fails the same probe and Arch ships loadkeys without xkb
# support. Disabling converges with Arch rather than diverging from it.
#
# The alternative was building libxkbcommon, and it is not close: measured, it
# wants libxcb and xkeyboard-config behind it -- an X11 subtree, to generate
# keymaps from an XKB database, on a mainframe with no graphics adapter.
set -euo pipefail
grep -q '^\s\+--disable-tests$' PKGBUILD || {
    echo "kbd: configure block not in the expected form" >&2; exit 1; }
sed -i 's|^\(\s*\)--disable-tests$|\1--disable-tests \\\n\1--disable-xkb|' PKGBUILD
[ "$(grep -c -- '--disable-xkb' PKGBUILD)" = 1 ] || {
    echo "kbd: --disable-xkb not inserted exactly once" >&2; exit 1; }
echo "kbd: --disable-xkb (host libxkbcommon-dev, installed for systemd, leaked in)"
