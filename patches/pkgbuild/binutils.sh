#!/usr/bin/env bash
# binutils: drop the gold linker.
#
#   make[1]: *** [Makefile:6798: all-gold] Error 2
#
# gold is x86-centric, deprecated upstream since binutils 2.44, and it is not
# built for s390x by any distribution that ships this architecture. Nothing
# links with it here: ld.bfd is the linker on Z.
#
# Dropped rather than debugged, because fixing gold for s390x would be work
# spent on a component upstream is removing.
set -euo pipefail
sed -i 's/--enable-gold[^ \\]*//' PKGBUILD
sed -i 's/^\(\s*\)--enable-gold.*$/\1--disable-gold \\/' PKGBUILD
grep -q -- '--enable-gold' PKGBUILD && { echo "binutils: gold still enabled" >&2; exit 1; }
echo "binutils: gold linker disabled (deprecated upstream, absent on s390x)"
