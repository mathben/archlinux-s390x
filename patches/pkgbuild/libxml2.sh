#!/usr/bin/env bash
# libxml2: the docs split assumes the docs were built.
#
#   mv: cannot stat '<pkgdir>/usr/share/doc': No such file or directory
#
# package_libxml2() ends on
#
#   mv "$pkgdir"/usr/share/doc -t doc/usr/share
#
# which feeds the libxml2-docs sub-package. On the build HOST the docs exist,
# because doxygen is installed there. Inside the stage-2 chroot they do not:
# that chroot has none of Arch's optional documentation tools, and
# build-stage2.sh wraps arch-meson with --auto-features auto precisely so a
# missing tool skips a feature instead of failing the build. The skipped
# feature then trips the split.
#
# FOURTH TIME THIS SHAPE APPEARS -- pam's PDFs, e2fsprogs' fuse2fs, cmake's
# emacs byte-compilation, and now this. A failure on the last line of
# package(), after a completely successful compile, naming a path rather than
# a reason. It has never once been a broken build.
#
# The move is made conditional rather than removed, because on the host the
# docs DO exist and belong in their own package. And libxml2-docs stays in
# pkgname: makepkg is content to produce an empty sub-package, and dropping it
# would diverge from Arch for a reason that only holds in one of the two
# stages.
set -euo pipefail
python3 - <<'ZZPY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()
old = '  mv "$pkgdir"/usr/share/doc -t doc/usr/share\n'
assert s.count(old) == 1, "libxml2: the docs move is not in the expected form"
new = ('  # Present when doxygen was available, absent in the stage-2 chroot, which\n'
       '  # has no documentation tools and builds with --auto-features auto.\n'
       '  if [ -d "$pkgdir"/usr/share/doc ]; then\n'
       '    mv "$pkgdir"/usr/share/doc -t doc/usr/share\n'
       '  fi\n')
s = s.replace(old, new, 1)
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
ZZPY
grep -q 'has no documentation tools' PKGBUILD || {
    echo "libxml2: the docs move was not made conditional" >&2; exit 1; }
echo "libxml2: docs split tolerates a build without doxygen"
