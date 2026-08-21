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

# --- no PGO+LTO build ---------------------------------------------------------
#
# binutils built at stage 1 and failed at stage 2, in gold:
#
#   <artificial>:(.text+0xc44e): undefined reference to
#     `void gold::gold_error_at_location<32, true>(...)'
#   collect2: error: ld returned 1 exit status
#
# `<artificial>` and the .ltrans object names are LTO's. It does not come from
# makepkg -- the chroot's OPTIONS carry !lto and LTOFLAGS is empty. It comes
# from the PKGBUILD itself: --enable-pgo-build=lto, a profile-guided build with
# link-time optimisation, which passes -flto=jobserver. gold's
# explicitly-instantiated templates do not survive it here.
#
# Stage 1 got away with it because the host's GCC did the work. Stage 2 uses
# ours, on s390x, at -O2 -march=z13 where stage 1 passed no flags at all.
#
# PGO and LTO are BUILD-TIME optimisations: dropping them changes how long
# binutils takes to compile and how fast the resulting linker runs, not what it
# can do. The alternatives were disabling gold -- removing a linker Arch ships
# -- or debugging an LTO template instantiation bug in a linker upstream has
# deprecated. For a bootstrap, a binutils that works beats a binutils that is
# five percent faster; PGO also roughly triples the build, which this port pays
# for on every stage.
python3 - <<'ZZPY'
import io, re
lines = io.open("PKGBUILD", encoding="utf-8").read().split("\n")
hit = [i for i, l in enumerate(lines) if "--enable-pgo-build" in l]
assert len(hit) == 1, "binutils: expected one --enable-pgo-build line, got %d" % len(hit)
i = hit[0]
assert lines[i].strip().startswith("--enable-pgo-build"), \
    "binutils: --enable-pgo-build shares its line: %r" % lines[i]
ind = re.match(r"^[ \t]*", lines[i]).group(0)
lines[i] = ind + "# --enable-pgo-build=lto removed: gold's templates do not survive"
lines.insert(i + 1, ind + "# LTO here, and PGO is build-time only -- no feature is lost.")
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lines))
ZZPY
grep -q "enable-pgo-build=lto removed" PKGBUILD || {
    echo "binutils: the PGO line was not commented" >&2; exit 1; }
grep -qE "^[[:space:]]*--enable-pgo-build" PKGBUILD && {
    echo "binutils: an active --enable-pgo-build line survived" >&2; exit 1; }
echo "binutils: PGO+LTO build dropped"
