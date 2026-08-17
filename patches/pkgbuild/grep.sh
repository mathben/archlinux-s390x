#!/usr/bin/env bash
# grep: skip ./bootstrap, which vets its host's autotools macros.
#
#   ./bootstrap: do not use pkg.m4 serial 12;
#   see https://lists.gnu.org/r/grep-devel/2025-04/msg00006.html
#
# grep is the only package in this list that INSPECTS the version of the m4
# macros its build host provides, and refuses to proceed on the serial Ubuntu
# ships. It is not detecting a real incompatibility on s390x -- the same
# refusal happens on any Ubuntu host, x86 included.
#
# The release tarball is already bootstrapped: configure, Makefile.in and the
# gnulib tree are present. Re-running ./bootstrap regenerates what is already
# there, so skipping it costs nothing.
set -euo pipefail
sed -i 's|^\(\s*\)\./bootstrap|\1# bootstrap skipped by the port: see patches/pkgbuild/grep.sh\n\1true|' PKGBUILD
grep -qE '^\s*\./bootstrap' PKGBUILD && { echo "grep: bootstrap still invoked" >&2; exit 1; }
echo "grep: ./bootstrap skipped (it rejects the host pkg.m4 serial)"
