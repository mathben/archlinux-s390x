#!/usr/bin/env bash
# binutils: install into /usr/lib, not /usr/lib64.
#
# THIS IS THE ROOT OF A CHAIN, and the chain is worth writing down because
# nothing in it looks related to anything else in it:
#
#   1. On s390x, GCC's and binutils' default MULTILIB_OSDIRNAME is lib64, so
#      binutils installs libiberty.a into /usr/lib64 -- creating that directory
#      as a REAL directory. On Arch, /usr/lib64 is a SYMLINK to lib.
#   2. meson chooses its default libdir by looking at the system: 64-bit plus a
#      real /usr/lib64 means "lib64". A symlink does not count, which is why
#      Arch never sees this and arch-meson passes no --libdir at all.
#   3. pkgconf is a meson package, so it installed into /usr/lib64 -- and
#      COMPILED IN its search path as /usr/lib64/pkgconfig.
#   4. Every .pc file in the distribution is in /usr/lib/pkgconfig. So every
#      pkg-config lookup inside the chroot failed. libxslt reported it as
#
#        configure: error: Package requirements (python-3.14) were not met:
#        Package 'python-3.14' not found
#
#      with python 3.14.7 installed and /usr/lib/pkgconfig/python-3.14.pc
#      sitting right there.
#
# Step 4 reads as a missing dependency. Step 1 is a linker library nobody
# thinks about. Fixing only the visible end -- pkgconf's search path -- would
# leave the real /usr/lib64 there, and the next meson package would land in it.
#
# --libdir is set explicitly rather than left to the target default, which is
# what Arch's layout means: one library directory, /usr/lib, with lib64 as a
# compatibility symlink.
set -euo pipefail
python3 - <<'ZZPY'
import io, re
lines = io.open("PKGBUILD", encoding="utf-8").read().split("\n")
hit = [i for i, l in enumerate(lines) if re.search(r"/configure\b", l) and "#" not in l.split("/configure")[0]]
assert len(hit) == 1, "binutils: expected one configure call, got %d" % len(hit)
i = hit[0]
indent = re.match(r"^[ \t]*", lines[i]).group(0)
assert lines[i].rstrip().endswith("\\"), "binutils: configure does not continue"
lines.insert(i + 1, indent + "  --libdir=/usr/lib \\")
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lines))
ZZPY
grep -A1 -E "/configure( |\\\\)" PKGBUILD | grep -q -- '--libdir=/usr/lib' || {
    echo "binutils: --libdir is not on the configure line" >&2; exit 1; }
echo "binutils: libdir pinned to /usr/lib (keeps /usr/lib64 a symlink)"
