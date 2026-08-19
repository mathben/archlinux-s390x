#!/usr/bin/env bash
# e2fsprogs: fuse2fs is built, deleted, and repackaged -- and none of that
# happens without fuse3 on the host.
#
#   rm: cannot remove '<pkgdir>/usr/bin/fuse2fs': No such file or directory
#
# package_e2fsprogs() removes fuse2fs so that package_fuse2fs() can ship it
# separately. The host has no fuse3, so misc/fuse2fs was never compiled, the
# path never existed, and the rm aborted package() AFTER a clean build -- the
# same shape as pam's PDF glob and util-linux's static libraries.
#
# THE PART WORTH CHECKING RATHER THAN PATCHING BLINDLY: making the rm tolerant
# is not enough on its own. fuse2fs is a SUB-PACKAGE, declared in pkgname, and
# package_fuse2fs() installs from misc/fuse2fs -- so it would fail next, on
# the same absent file. And its depends=('fuse3' 'e2fsprogs') names fuse3,
# which this port does not build, so even a successful package would be
# uninstallable. Three reasons pointing the same way.
#
# e2fsprogs is in stage 1 for libcom_err.so and libss.so, which krb5 needs
# after --with-system-ss was dropped. A FUSE mount helper is not part of that.
#
# Deferred, not architectural: build fuse3, add it to the closure, and both
# the sub-package and the rm come back on their own. TODO.md records it.
set -euo pipefail
python3 - <<'PY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()

old = "pkgname=('e2fsprogs' 'fuse2fs')"
assert s.count(old) == 1, "e2fsprogs: pkgname line not in the expected form"
s = s.replace(old, "pkgname=('e2fsprogs')", 1)

# The rm keeps its -f rather than being deleted: with fuse3 present the files
# WOULD exist and must still be removed from the main package.
old = '  rm "${pkgdir}"/usr/{bin/fuse2fs,share/man/man1/fuse2fs.1}\n'
assert s.count(old) == 1, "e2fsprogs: fuse2fs removal not in the expected form"
s = s.replace(old, '  rm -f "${pkgdir}"/usr/{bin/fuse2fs,share/man/man1/fuse2fs.1}\n', 1)

io.open("PKGBUILD", "w", encoding="utf-8").write(s)
PY
grep -q "^pkgname=('e2fsprogs')$" PKGBUILD || {
    echo "e2fsprogs: fuse2fs not dropped from pkgname" >&2; exit 1; }
grep -qF 'rm -f "${pkgdir}"/usr/{bin/fuse2fs' PKGBUILD || {
    echo "e2fsprogs: fuse2fs removal not made tolerant" >&2; exit 1; }
echo "e2fsprogs: fuse2fs dropped (no fuse3 on the host, none in the closure)"
