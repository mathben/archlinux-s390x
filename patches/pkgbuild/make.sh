#!/usr/bin/env bash
# make: it declares guile, and our make has no guile in it.
#
#   depends=('glibc' 'guile')
#
# GNU make's configure AUTO-DETECTS guile -- the PKGBUILD passes a bare
# `./configure --prefix=/usr` and says nothing about it. This build host has
# no guile at all, so the $(guile ...) function was never compiled in, and the
# artefact says so plainly:
#
#   $ readelf -d usr/bin/make | grep NEEDED
#     (NEEDED) Shared library: [libc.so.6]
#
# One library. Nothing else.
#
# THE TRAP is that nothing fails. --nodeps means makepkg never checks the
# declaration, so make built, passed, and entered the repository asking for a
# package this port does not have and does not need. It is the same class as
# gcc-libs declaring libhwasan: a dependency that is real in Arch's build
# environment and false in ours, and the only thing that ever notices is
# pacman, at install time, long after the cause.
#
# It is worth the entry it costs. guile drags in bdw-gc and libffi behind it,
# so this single false line was three packages of closure for a feature the
# binary does not contain.
#
# WHY REMOVE RATHER THAN BUILD. Because the declaration should describe THIS
# artefact. Building guile and rebuilding make would be the other honest
# answer and would match Arch exactly -- TODO.md records it as deferred, with
# the cost, so the choice stays visible. What is not defensible is shipping a
# make that claims a feature it lacks.
set -euo pipefail
grep -q "^depends=('glibc' 'guile')$" PKGBUILD || {
    echo "make: depends line is not the expected ('glibc' 'guile')" >&2; exit 1; }
sed -i "s/^depends=('glibc' 'guile')$/depends=('glibc')/" PKGBUILD
grep -q "^depends=('glibc')$" PKGBUILD || {
    echo "make: guile not removed from depends" >&2; exit 1; }
echo "make: guile dropped from depends (the binary links libc only)"
