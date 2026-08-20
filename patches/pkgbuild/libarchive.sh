#!/usr/bin/env bash
# libarchive: no xar during the bootstrap.  STAGE 1 ONLY.
#
# THE CYCLE, exactly as it presented itself. Stage 2 reached its very first
# packaging step and stopped on
#
#   bsdtar: error while loading shared libraries: libicuuc.so.76
#   ==> ERROR: Failed to create package file.
#
# after libxml2 had compiled and installed perfectly. The chain:
#
#   bsdtar -> libarchive.so.13 -> libxml2.so.16 -> libicuuc.so.76
#
# The libxml2 in the chroot is our own stage-1 build, and stage 1 builds
# against the HOST, whose ICU is 76. Our icu package ships 78. So bsdtar
# cannot start -- and bsdtar is what makepkg uses to write the package. The
# package that would fix it is the one being built. Nothing can come out of
# the chroot until this is broken from outside.
#
# WHY NOT SUPPLY libicuuc.so.76. Copying the host's ICU into the chroot is the
# obvious move and it is the wrong one: it puts untracked host binaries in
# /usr/lib, which is precisely what test-chroot.sh's ARTEFACT check exists to
# catch. A symlink to 78 does not work either -- ICU version-suffixes every
# symbol, so libicuuc.so.78 does not define u_strlen_76.
#
# THE ROOT is that libarchive links libxml2 at all. It wants it for the xar
# format, which is an Apple installer container. Nothing in this bootstrap
# reads one: makepkg writes .pkg.tar.gz, pacman reads it. Dropping xar removes
# the entire ICU chain rather than papering over its version.
#
# STAGE 1 ONLY -- build-stage2.sh lists libarchive in STAGE2_SKIP_HOOKS. Stage
# 2 builds it as Arch does, with xar, against our own libxml2 and icu, where
# the versions agree. The divergence lives exactly as long as the cycle does.
#
# BOTH depends ARRAYS. libxml2 is declared twice: once at the top and once as
# libxml2.so in the depends+= inside package(). Removing only the visible one
# leaves the package uninstallable for a reason the diff appears to fix -- the
# fifth place, and the one that has cost the most time in this port.
set -euo pipefail
python3 - <<'ZZPY'
import io, re
s = io.open("PKGBUILD", encoding="utf-8").read()

# ./configure: refuse xar outright. libarchive probes for BOTH libxml2 and
# expat and uses whichever it finds, so declining only one leaves the other
# to reintroduce the dependency the day the host installs it.
old = "      --without-nettle \\\n"
assert s.count(old) == 1, "libarchive: --without-nettle is not where expected"
s = s.replace(old, old + "      --without-xml2 \\\n      --without-expat \\\n", 1)

# depends=(...): the top-level array.
old = "         'libxml2'\n"
assert s.count(old) == 1, "libarchive: 'libxml2' not in depends as expected"
s = s.replace(old, "", 1)

# depends+=(...) inside package(): the soname form.
old = "    'libxml2.so'\n"
assert s.count(old) == 1, "libarchive: 'libxml2.so' not in package() depends"
s = s.replace(old, "", 1)

io.open("PKGBUILD", "w", encoding="utf-8").write(s)
ZZPY
grep -q -- '--without-xml2' PKGBUILD || { echo "libarchive: xar not disabled" >&2; exit 1; }
# Nothing named libxml2 may remain in ANY depends array -- checked by counting
# rather than by eye, because there were two and both looked like the only one.
if grep -nE "^\s*'?libxml2" PKGBUILD | grep -q .; then
    echo "libarchive: a libxml2 dependency survived:" >&2
    grep -nE "^\s*'?libxml2" PKGBUILD >&2
    exit 1
fi
echo "libarchive: xar disabled, libxml2 dropped from both depends arrays"
