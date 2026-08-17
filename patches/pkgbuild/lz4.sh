#!/usr/bin/env bash
# lz4: bare `meson setup`, so libdir lands on the Debian multiarch path.
#
# This PKGBUILD calls meson directly -- not arch-meson -- so nothing supplies
# --libdir and meson falls back to default_libdir(), which asks the HOST
# where libraries go. On this Debian-flavoured builder the answer comes from
# dpkg-architecture -qDEB_HOST_MULTIARCH, i.e. lib/s390x-linux-gnu. The
# package built, exited 0, and shipped:
#
#   usr/lib/s390x-linux-gnu/liblz4.so.1.10.0
#   usr/lib/s390x-linux-gnu/pkgconfig/liblz4.pc
#
# Arch's ld.so and pkgconf only read /usr/lib, so on the target every consumer
# fails to link and `pkg-config liblz4` finds nothing -- while the PKGBUILD
# still declares provides=('liblz4.so'), a promise the artefact does not keep.
# The binaries in usr/bin work, which is exactly what makes it look fine.
#
# The damage is twofold: liblz4.pc is not merely in the wrong directory, its
# body also reads libdir=${prefix}/lib/s390x-linux-gnu, so relocating the file
# would not have been enough. Setting libdir fixes both at once.
#
# Anchor on "meson setup", NOT on "meson": build() also runs meson configure
# and meson compile, package() runs meson install, and check() runs
# build/meson/programs/lz4 -- a PATH containing the word. There is exactly one
# setup, asserted below.
#
# --libdir survives the later `meson configure`, which only rewrites the
# options it is handed (-Dcontrib -Dexamples -Dprograms).
set -euo pipefail
python3 - <<'PY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()
old = "meson setup --prefix=/usr --buildtype=plain"
n = s.count(old)
assert n == 1, "lz4: expected exactly 1 meson setup, found %d" % n
s = s.replace(old, "meson setup --prefix=/usr --libdir=lib --buildtype=plain", 1)
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
PY
[ "$(grep -c -- '--libdir=lib' PKGBUILD)" = 1 ] || {
    echo "lz4: --libdir=lib not applied exactly once" >&2; exit 1; }
echo "lz4: meson libdir pinned to lib (host default is lib/s390x-linux-gnu)"
