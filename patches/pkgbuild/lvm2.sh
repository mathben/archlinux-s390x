#!/usr/bin/env bash
# lvm2: only device-mapper is wanted, and the lvm2 half costs a Rust toolchain.
#
# The chain that puts this PKGBUILD in stage 1 is
# systemd -> cryptsetup -> device-mapper, and device-mapper is one of the two
# packages this source produces. Nothing in the repository asks for `lvm2`
# itself -- checked across every .PKGINFO, the only consumer of device-mapper
# is cryptsetup, and the only consumer of lvm2 is lvm2's own dependency on
# device-mapper.
#
# What the lvm2 half brings with it:
#
#   thin-provisioning-tools -- rewritten in Rust. Its prepare() stops on
#     `error: Error loading target specification: Could not find
#      specification for target "host-tuple"`, and behind that stands cargo,
#     a crates.io fetch and the whole Rust bootstrap question. This port
#     already declined that detour once, for python-cryptography.
#
#   libaio -- and not usefully. Ubuntu renamed its library libaio.so.1t64 for
#     the time64 ABI transition, so the lvm2 binaries link a soname Arch has
#     never had. Building Arch's libaio would not change what stage 1 links.
#
# Both leave the closure with the sub-package, which is why this is one hook
# rather than three.
#
# THE MEASUREMENT IS THE ARGUMENT, and it is the same one that went the other
# way for tcl and unixodbc an hour earlier. Those cost zero new packages, so
# building them beat dropping a sub-package. This one costs a language
# runtime, so dropping wins. The rule is not "prefer dropping" or "prefer
# building" -- it is to measure each time.
#
# Deferred: a target that wants LVM builds Rust first, restores the sub-package
# and rebuilds. device-mapper alone is what dm-crypt and systemd need.
set -euo pipefail
python3 - <<'PY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()
old = "pkgname=('lvm2' 'device-mapper')"
assert s.count(old) == 1, "lvm2: pkgname line not in the expected form"
s = s.replace(old, "pkgname=('device-mapper')", 1)
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
PY
grep -q "^pkgname=('device-mapper')$" PKGBUILD || {
    echo "lvm2: sub-package not reduced to device-mapper" >&2; exit 1; }
# package_lvm2() stays in the file, uncalled -- makepkg never calls a function
# whose name is absent from pkgname, as with package_libquadmath() in gcc.
grep -q "^package_device-mapper()" PKGBUILD || {
    echo "lvm2: device-mapper package function missing" >&2; exit 1; }
echo "lvm2: only device-mapper built (lvm2 would pull Rust via thin-provisioning-tools)"

# device-mapper also picked up the host's libselinux, silently.
#
#   $ readelf -d usr/bin/dmsetup | grep NEEDED
#     (NEEDED) Shared library: [libselinux.so.1]
#
# Seventh package in this port to do it, and the second found by the soname
# audit rather than by a build. lvm2's configure has --disable-selinux and
# defaults to detecting; Ubuntu's libselinux1-dev is present because
# libmount-dev and libglib2.0-dev pull it in, so it detected.
#
# Arch has no libselinux package at all -- the reason coreutils, findutils,
# sed, tar and gettext each carry the same three lines. This is the sixth
# copy, and TODO.md already records that the per-package hook does not scale
# to a probe every package can trip.
python3 - <<'PY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()
assert "--disable-selinux" not in s, "lvm2: selinux already disabled, hook ran twice"
anchor = "    --enable-cmdlib \\\n"
assert s.count(anchor) == 1, "lvm2: configure block not in the expected form"
s = s.replace(anchor, "    --disable-selinux \\\n" + anchor, 1)
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
PY
[ "$(grep -c -- '--disable-selinux' PKGBUILD)" = 1 ] || {
    echo "lvm2: --disable-selinux not inserted exactly once" >&2; exit 1; }
echo "lvm2: --disable-selinux (Arch has no libselinux; the host does)"
