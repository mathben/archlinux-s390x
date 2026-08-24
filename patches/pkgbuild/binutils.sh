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
import io
# DELETED, not commented.
#
# The first version replaced the line with a comment, and binutils then failed
# with
#
#   /build/binutils/PKGBUILD: line 107: --enable-plugins: command not found
#
# because the line ended in a backslash. A comment inside a continued command
# does not comment out an option -- it breaks the continuation, and the NEXT
# option becomes a command of its own. The documented trap in this port was the
# mirror image (commenting the first line of a multi-line assignment leaves the
# continuations live); this is the same fact from the other side.
#
# Nothing is left in its place: the explanation belongs in this hook, and any
# comment placed inside the configure invocation would break it again.
lines = io.open("PKGBUILD", encoding="utf-8").read().split("\n")
hit = [i for i, l in enumerate(lines) if "--enable-pgo-build" in l]
assert len(hit) == 1, "binutils: expected one --enable-pgo-build line, got %d" % len(hit)
i = hit[0]
assert lines[i].strip().startswith("--enable-pgo-build"), \
    "binutils: --enable-pgo-build shares its line: %r" % lines[i]
del lines[i]
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lines))
ZZPY
grep -qE "^[[:space:]]*--enable-pgo-build" PKGBUILD && {
    echo "binutils: an active --enable-pgo-build line survived" >&2; exit 1; }
echo "binutils: PGO+LTO build dropped"

# --- no gold, and no s390-specific extra target -------------------------------
#
# This section was written twice, and the first version was wrong in an
# instructive way.
#
# gold would not link:
#
#   s390.cc: undefined reference to `gold::gold_error_at_location<32, true>'
#
# gold's s390 target file compiles for both s390 and s390x and needs <32, true>
# template instantiations, which exist only when a 32-bit s390 target is
# configured. The PKGBUILD asked for --enable-targets=x86_64-pep, so the first
# fix translated that to s390-linux-gnu -- the honest-looking equivalent. bfd's
# configure answered:
#
#   *** Specify --enable-obsolete to build it anyway.
#   *** Support will be REMOVED in the next major release of BINUTILS,
#   *** unless a maintainer comes forward.
#
# 32-bit s390 is OBSOLETE in binutils. So gold on s390x cannot be built without
# enabling a target upstream has announced it is deleting -- and gold itself is
# deprecated, with bfd ld the default here already (--enable-ld=default). Turning
# on one deprecated thing to build another is not a trade worth making.
#
# So: gold is dropped, and the extra target list keeps only bpf-unknown-none,
# which is architecture-neutral. x86_64-pep goes because it names a format for a
# machine this is not.
#
# WHAT IS LOST: /usr/bin/ld.gold. Nothing in this port invokes it, ld is the
# default, and upstream is removing gold. Recorded rather than hidden -- the
# stage-2 binutils will not match Arch's file list, and this is why.
set -euo pipefail
python3 - <<'ZZPY'
import io, re
lines = io.open("PKGBUILD", encoding="utf-8").read().split("\n")

t = [i for i, l in enumerate(lines) if "--enable-targets=" in l]
assert len(t) == 1, "binutils: expected one --enable-targets, got %d" % len(t)
assert "x86_64-pep" in lines[t[0]], "binutils: --enable-targets is not the x86 one: %r" % lines[t[0]]
lines[t[0]] = lines[t[0]].replace("x86_64-pep,", "")

g = [i for i, l in enumerate(lines) if re.match(r"^[ \t]*--enable-gold[ \t]*\\?$", l)]
assert len(g) == 1, "binutils: expected one --enable-gold line, got %d" % len(g)
lines[g[0]] = lines[g[0]].replace("--enable-gold", "--disable-gold")

io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lines))
ZZPY
grep -q "x86_64-pep" PKGBUILD && { echo "binutils: an x86_64 target survived" >&2; exit 1; }
grep -q -- "--disable-gold" PKGBUILD || { echo "binutils: gold not disabled" >&2; exit 1; }
grep -q -- "--enable-gold" PKGBUILD && { echo "binutils: gold still enabled" >&2; exit 1; }
echo "binutils: gold dropped (its s390 support needs an obsolete target)"

# --- libiberty still records a usr/lib64 path ---------------------------------
#
# --libdir=/usr/lib above is not enough. pacman refused to install the result:
#
#   binutils: <root>/usr/lib64 exists in filesystem (owned by filesystem)
#   binutils: <root>/usr/lib64/libiberty.a exists in filesystem
#
# libiberty installs into $(libdir)$(MULTIOSSUBDIR), and on s390x gcc reports
# ../lib64 for -print-multi-os-directory. In the INSTALLED system that resolves
# through the symlink the filesystem package now provides, so the file lands in
# /usr/lib -- but pkgdir has no such symlink, so make creates a real
# pkg/usr/lib64/ and makepkg records `usr/lib64/libiberty.a` as the package's
# own path. Installing it then collides with the symlink.
#
# The two fixes are not alternatives: filesystem's symlink is what keeps meson
# and cmake choosing lib, and this moves the one file that still writes through
# the multi-os subdirectory. Done in package(), on pkgdir, so nothing depends on
# the order the two packages are installed in.
python3 - <<'ZZPY'
import io, re
lines = io.open("PKGBUILD", encoding="utf-8").read().split("\n")
# The last package function is where pkgdir is complete.
# package(), not package_binutils(). binutils is NOT a split package here --
# pkgname=binutils, one function -- and the first version of this assumed the
# split form and asserted its way out. Both shapes are in this port; a hook has
# to look.
hit = [i for i, l in enumerate(lines) if re.match(r"^package(_binutils)?\(\)", l)]
assert len(hit) == 1, "binutils: expected one package function, got %d" % len(hit)
# Find that function's closing brace.
i = hit[0] + 1
while i < len(lines) and lines[i] != "}":
    i += 1
assert i < len(lines), "binutils: package_binutils() has no closing brace"
lines[i:i] = [
    "",
    "  # libiberty writes through gcc's multi-os subdirectory (../lib64 on",
    "  # s390x). In the installed system usr/lib64 is a symlink to lib, but pkgdir",
    "  # has no symlink, so the path is recorded literally and collides with the",
    "  # filesystem package. Move it to where it resolves to anyway.",
    '  if [ -d "$pkgdir/usr/lib64" ]; then',
    '    install -d "$pkgdir/usr/lib"',
    '    mv "$pkgdir"/usr/lib64/* "$pkgdir/usr/lib/"',
    '    rmdir "$pkgdir/usr/lib64"',
    '  fi',
]
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lines))
ZZPY
grep -q 'rmdir "\$pkgdir/usr/lib64"' PKGBUILD || {
    echo "binutils: the lib64 move was not inserted" >&2; exit 1; }
echo "binutils: libiberty moved out of usr/lib64"
