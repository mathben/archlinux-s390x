#!/usr/bin/env bash
# gcc: keep only the front ends that bootstrap without an existing compiler
# of the same language.
#
#   configure: error: GNAT is required to build ada
#   configure: error: GDC is required to build d
#
# Ada and D are written in themselves: building their front ends needs an
# existing Ada or D compiler of a compatible vintage. Ubuntu ships gnat, but
# not one GCC 15 accepts, and D has no bootstrap compiler here at all.
# Modula-2 and COBOL have the same shape of problem.
#
# Nothing in a core bootstrap -- and nothing in ERPLibre -- is written in any
# of them. C, C++, Fortran, LTO and the Objective-C front ends cover
# everything the rest of this port compiles.
#
# STAGE 1 CONCESSION, not a permanent one. Once the port is self-hosting its
# own gcc can bootstrap the others, and this hook should be revisited.
set -euo pipefail
sed -i 's/^\(\s*--enable-languages=\).*\\$/\1c,c++,fortran,lto,objc,obj-c++ \\/' PKGBUILD
grep -m1 -- '--enable-languages' PKGBUILD
grep -qE 'enable-languages=[^ ]*(ada|,d,|m2|cobol)' PKGBUILD && {
    echo "gcc: a self-hosted front end is still enabled" >&2; exit 1; }
echo "gcc: front ends reduced to those that bootstrap from C"
