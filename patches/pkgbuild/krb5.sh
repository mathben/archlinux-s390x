#!/usr/bin/env bash
# krb5: --with-system-ss, and Ubuntu ships no ss headers.
#
#   checking whether system ss package works... configure: error: cannot run
#   test program
#
# THE TRAP is that message. "cannot run test program" reads like a broken
# cross-compile or a missing loader -- the kind of thing that sends you into
# config.log looking for a link failure on this architecture. It is neither.
# The subsystem library (ss, from e2fsprogs) has no development package on
# Ubuntu at all: libss2 is runtime-only, libss-dev does not exist, and
# e2fslibs-dev has no candidate. There is no ss.h to compile against, so the
# test program cannot be built, let alone run.
#
# Note what IS present, so the two are not confused: --with-system-et works,
# because comerr-dev ships /usr/include/et/com_err.h. Only ss is missing.
#
# krb5 carries its own copy of the subsystem library and uses it when not told
# otherwise, so dropping the flag costs nothing but a slightly larger binary.
# Building e2fsprogs to supply one header would be the other answer; it is not
# worth a package in the closure, and TODO.md records the choice.
set -euo pipefail
grep -qE '^\s+--with-system-ss \\$' PKGBUILD || {
    echo "krb5: --with-system-ss line not in the expected form" >&2; exit 1; }
[ "$(grep -c -- '--with-system-ss' PKGBUILD)" = 1 ] || {
    echo "krb5: expected exactly one --with-system-ss" >&2; exit 1; }
sed -i '/^\s\+--with-system-ss \\$/d' PKGBUILD
grep -q -- '--with-system-ss' PKGBUILD && {
    echo "krb5: --with-system-ss survived" >&2; exit 1; }
echo "krb5: uses its bundled ss (Ubuntu has no ss development package)"
