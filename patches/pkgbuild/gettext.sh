#!/usr/bin/env bash
# gettext: --without-selinux. The sixth package to pick up the host's
# libselinux, and the first one nothing warned about.
#
#   $ readelf -d usr/lib/libgettextlib-1.0.so | grep NEEDED
#     (NEEDED) Shared library: [libselinux.so.1]
#
# Nothing failed. gettext built, passed, and went into the repository with a
# library linked against something Arch has no package for -- the artefact
# audit is the only thing that found it, exactly as it found coreutils,
# findutils, sed and tar before it.
#
# WHY IT CAME BACK. Those four were fixed with per-package hooks, and the
# reasoning at the time was that the same gnulib probe "catches findutils, sed
# and tar" -- a list of the packages then in the build. gettext was not in the
# port yet. It arrived with the dependency closure, uses gnulib too, probes
# selinux/selinux.h unconditionally, and found Ubuntu's libselinux1-dev
# sitting where it always was.
#
# So this is the fifth copy of one three-line fix, and that is the real
# finding: the per-package hook does not scale to a probe that any gnulib
# package can trip. The alternative -- exporting
# ac_cv_header_selinux_selinux_h=no once in build_package -- was considered
# and rejected when coreutils was fixed, on the grounds that a global cache
# override is invisible at the point where it acts. That trade has now been
# paid for five times. TODO.md records it as a decision to revisit rather than
# leaving the next person to rediscover the arithmetic.
#
# Arch's gettext links no libselinux, so this converges with Arch.
set -euo pipefail
grep -q '^    --without-included-libunistring$' PKGBUILD || {
    echo "gettext: configure block not in the expected form" >&2; exit 1; }
sed -i 's|^\(    --without-included-libunistring\)$|\1 \\\n    --without-selinux|' PKGBUILD
[ "$(grep -c -- '--without-selinux' PKGBUILD)" = 1 ] || {
    echo "gettext: --without-selinux not inserted exactly once" >&2; exit 1; }
echo "gettext: --without-selinux (gnulib found the host's libselinux)"
