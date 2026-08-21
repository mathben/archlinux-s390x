#!/usr/bin/env bash
# gcc: three x86 assumptions, all fatal on s390x.
#
# 1. Front ends written in themselves.
#
#      configure: error: GNAT is required to build ada
#      configure: error: GDC is required to build d
#
#    Ada and D need an existing compiler of the same language; Modula-2 and
#    COBOL have the same shape. Nothing in a core bootstrap, and nothing in
#    ERPLibre, is written in any of them.
#
# 2. Multilib, which on Z means the 31-bit ABI:
#
#      configure: error: Support for -m31 is deprecated and will be removed.
#      Specify --enable-obsolete to build it anyway.
#
#    On x86_64 multilib means i686 and Arch wants it. Here it means the
#    31-bit ESA/390 ABI that GCC is actively removing. Disabled rather than
#    resurrected as obsolete.
#
# 3. The lib32 split package and every _pick that feeds it.
#
# The front-end reduction is a STAGE 1 CONCESSION: once the port is
# self-hosting, its own gcc can bootstrap Ada and D. The multilib and lib32
# removals are permanent -- they are architectural.
set -euo pipefail

# Only the MAIN build. The PKGBUILD configures gcc twice: once for the
# compiler, once for libgccjit with --enable-languages=jit. Rewriting
# every occurrence clobbered the second one, so the jit tree built a
# compiler instead of a library and package() died on
#   cp: cannot stat 'gcc/libgccjit.so*': No such file or directory
# after forty minutes of compiling. Match the language list, never 'jit'.
sed -i '/--enable-languages=jit/!s/^\(\s*--enable-languages=\).*\\$/\1c,c++,fortran,lto,objc,obj-c++ \\/' PKGBUILD
if grep -qE 'enable-languages=[^ ]*(ada|,d,|m2|cobol)' PKGBUILD; then
    echo "gcc: a self-hosted front end is still enabled" >&2; exit 1
fi

if grep -q -- '--enable-multilib' PKGBUILD; then
    sed -i 's/--enable-multilib/--disable-multilib/' PKGBUILD
else
    sed -i 's/^\(\s*\)--enable-languages=\(.*\)$/\1--disable-multilib \\\n\1--enable-languages=\2/' PKGBUILD
fi
grep -q -- '--disable-multilib' PKGBUILD || { echo "gcc: multilib not disabled" >&2; exit 1; }

# The pkgname array lists one sub-package per front end. makepkg calls
# package_<name>() for every entry, so those whose language is now off would
# package an empty tree. Names absent from the array are never called, so
# pruning it is enough -- the functions themselves can stay.
python3 - <<'PY'
import io, re
drop = {
    "gcc-ada", "gcc-d", "gcc-gcobol", "gcc-go", "gcc-m2", "gcc-rust",
    "libgm2", "libgo", "libgphobos", "libgcobol",
    "lib32-gcc-libs",
    # __float128 est propre a x86 et ia64. s390x configure libquadmath
    # -- le repertoire ne contient qu un Makefile et un config.log -- mais
    # ne batit aucune bibliotheque, d ou l arret sur
    #   mv: cannot stat 'usr/lib/libquadmath.a'
    "libquadmath",
    # Hardware-assisted ASan exists on x86_64 and aarch64 only.
    "libhwasan",
}
s = io.open("PKGBUILD", encoding="utf-8").read()
m = re.search(r"^pkgname=\(\n(.*?)^\)$", s, re.S | re.M)
assert m, "pkgname array not found"
kept = [ln for ln in m.group(1).splitlines() if ln.strip() not in drop]
s = s[:m.start(1)] + "\n".join(kept) + "\n" + s[m.end(1):]
s = re.sub(r"\npackage_lib32-gcc-libs\(\)\s*\{.*?\n\}\n", "\n", s, flags=re.S)
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
print("gcc: sub-packages kept -> %d" % len(kept))
PY

# Two lingering references outside the array: a makedepends entry on a
# package that does not exist for this architecture, and a run of
# `_pick lib32-gcc-libs usr/lib32/...` splitting out files multilib would
# have produced. With multilib off, usr/lib32 is empty.
sed -i '/^\s*lib32-gcc-libs\s*$/d' PKGBUILD
sed -i '/_pick lib32-gcc-libs/d' PKGBUILD
sed -i '/lib32-gcc-libs: for generating code/d' PKGBUILD

# package_gcc() still manipulates the 32-bit tree in several places, and
# every one of them fails once multilib is off, because usr/lib32 never
# exists:
#
#   'usr/lib/gcc/s390x-ibm-linux-gnu/16/libatomic.so' -> '../../../libatomic.so'
#   ln: No such file or directory
#
# The link that is reported is the one that SUCCEEDED; the failure is the
# usr/lib32 line right after it, in the same loop. Reading the error alone
# sends you hunting for a missing libatomic that is in fact present.
sed -i '/usr\/lib32/d; /_libdir\/32/d' PKGBUILD
# Some 32-bit paths are written out in full rather than through
# $_libdir/32, so the pattern above misses them:
#   mv: cannot stat 'usr/lib/gcc/s390x-ibm-linux-gnu/16/32/finclude/'
sed -i '/_pick .*\/32\//d' PKGBUILD
# Others write BOTH paths with a brace expansion -- $_libdir/{,32/}finclude/
# expands to the normal and the 32-bit path in one go. Deleting the line
# would lose the normal path too, so only the 32-bit alternative goes.
sed -i 's|{,32/}||g; s|{,32}||g' PKGBUILD

# s390x GCC installs 64-bit libraries into usr/lib64; Arch's layout is usr/lib
# everywhere. package_gcc() therefore looked for files that were one directory
# away:
#
#   mv: cannot stat 'usr/lib/libgfortran.spec': No such file or directory
#
# while the file sat in usr/lib64/libgfortran.spec. This is not one stray
# file -- lib64 is GCC's default MULTILIB_OSDIRNAMES for 64-bit Z, so the
# whole package layout is affected, and every _pick that names usr/lib would
# miss in the same way.
#
# The trees are merged before any _pick runs, which keeps the upstream
# package definitions working unchanged rather than rewriting each path.
python3 - <<'PY'
import io, re
s = io.open("PKGBUILD", encoding="utf-8").read()
merge = """  # s390x installs 64-bit libraries to lib64; Arch expects lib.
  if [ -d usr/lib64 ]; then
    mkdir -p usr/lib
    cp -a usr/lib64/. usr/lib/
    rm -rf usr/lib64
  fi
"""
i = s.index("    _pick ")
s = s[:i] + merge + s[i:]
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
PY
grep -q 'installs 64-bit libraries to lib64' PKGBUILD || {
    echo "gcc: lib64 merge not inserted" >&2; exit 1; }
echo "gcc: lib64 merged into lib before packaging"
if grep -qE '_pick .*(\{,32|/32/)' PKGBUILD; then
    echo "gcc: a 32-bit _pick path remains" >&2; exit 1
fi

# The same loop links the D runtimes, which do not exist now that the D
# front end is off.
sed -i 's/^\(\s*for _so in \).*; do$/\1libatomic.so libstdc++.so; do/' PKGBUILD

# package_gcc() also _picks files out for every sub-package, including the
# front ends we disabled. _pick is a mv, so it fails on what was never built:
#
#   mv: cannot stat 'usr/bin/gnat': No such file or directory
#
# Dropping the entries from pkgname was not enough -- the _pick lines live in
# package_gcc() and run regardless of which sub-packages are requested.
for _lang in gcc-ada gcc-d gcc-go gcc-m2 gcc-rust gcc-gcobol libquadmath \
             libgm2 libgo libgphobos libgcobol libhwasan; do
    sed -i "/_pick ${_lang} /d" PKGBUILD
done
if grep -qE '_pick (gcc-ada|gcc-d|gcc-go|gcc-m2|gcc-rust|gcc-gcobol) ' PKGBUILD; then
    echo "gcc: _pick lines remain for a disabled front end" >&2; exit 1
fi

if grep -q 'usr/lib32' PKGBUILD; then
    echo "gcc: usr/lib32 still manipulated" >&2; exit 1
fi
if grep -qE 'for _so in .*(gdruntime|gphobos)' PKGBUILD; then
    echo "gcc: D runtimes still in the symlink loop" >&2; exit 1
fi
grep -m1 'for _so in' PKGBUILD | sed 's/^\s*//'

# Verify what matters: the array makepkg iterates. Grepping the whole file
# for the bare name declared a false failure once already, on libtool and
# then here -- the string survives in comments and in unused functions.
if sed -n '/^pkgname=(/,/^)/p' PKGBUILD | grep -q 'lib32'; then
    echo "gcc: lib32 still in pkgname array" >&2; exit 1
fi
grep -m1 -- '--enable-languages' PKGBUILD

# libgccjit: OPTIONAL, and off by default.
#
# Arch configures and compiles the entire gcc source tree a SECOND time just
# for libgccjit -- it needs --enable-host-shared, which would slow the main
# compiler down if applied to it. That second pass is roughly half of gcc's
# build time, and on this hardware that is twenty minutes per attempt.
#
# Nothing in the bootstrap needs it, and neither does ERPLibre. It is
# skipped by default and re-enabled with:
#
#     EL_GCC_JIT=1 bash scripts/build-stage1.sh
#
# When enabled, nothing below runs and the PKGBUILD keeps its upstream
# behaviour, including the --enable-languages=jit line the main-build sed
# deliberately leaves alone.
if [ "${EL_GCC_JIT:-0}" != "1" ]; then
    python3 - <<'PY'
import io, re
s = io.open("PKGBUILD", encoding="utf-8").read()
# The second configure pass, from its comment to the copy of the .so.
s = re.sub(
    r"\n  # Build libgccjit separately.*?\n  cp -a gcc/libgccjit\.so\* \.\./gcc-build/gcc/\n",
    "\n", s, flags=re.S)
# Its package function, the _pick lines that feed it, and its pkgname entry.
s = re.sub(r"\npackage_libgccjit\(\)\s*\{.*?\n\}\n", "\n", s, flags=re.S)
s = "\n".join(l for l in s.split("\n")
               if "_pick libgccjit" not in l
               and l.strip() != "libgccjit"
               and "mkdir -p \"$srcdir\"/libgccjit-build" not in l)
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
PY
    # package_gcc() also installs the jit artefacts explicitly:
    #   make -C gcc DESTDIR="$pkgdir" jit.install-common jit.install-info
    # Removing the build block and the pkgname entry was not enough --
    # this line runs in the MAIN package function and fails on a library
    # that was never built:
    #   install: cannot install libgccjit.so.0.0.1
    sed -i '/jit\.install-common/d' PKGBUILD
    if grep -q 'libgccjit-build' PKGBUILD; then
        echo "gcc: libgccjit build block remains" >&2; exit 1
    fi
    if sed -n '/^pkgname=(/,/^)/p' PKGBUILD | grep -q 'libgccjit'; then
        echo "gcc: libgccjit still in pkgname array" >&2; exit 1
    fi
    echo "gcc: libgccjit skipped (set EL_GCC_JIT=1 to build it)"
else
    echo "gcc: libgccjit ENABLED (second full build of the tree)"
fi
echo "gcc: front ends reduced, multilib off, lib32 removed"
# Bound the parallelism of gcc's own bootstrap, INSIDE the PKGBUILD.
#
# With MAKEFLAGS=-j16 the stage-2 bootstrap raced against itself:
#
#   /usr/include/strings.h:23:10: fatal error:
#     .../gcc-build/prev-gcc/include/stddef.h: No such file or directory
#
# The file was PRESENT when the tree was inspected afterwards. It is not
# missing -- it is generated by a rule another rule consumes without
# declaring the dependency, and sixteen jobs win that race often enough to
# fail. Read as an absent header, it sends you hunting through include paths
# for nothing.
#
# The setting has to go into build(): this hook runs in its own bash process,
# so exporting MAKEFLAGS here would never reach makepkg. gcc is the only
# package in the list that bootstraps itself three times, so the bound is
# applied here rather than globally.
sed -i '0,/^build() {$/s//build() {\n  export MAKEFLAGS="-j8"/' PKGBUILD
grep -A1 '^build() {' PKGBUILD | head -2 | sed 's/^/  /'

# THE FIFTH PLACE. The repository already knew a component is removed in four
# independent places -- pkgname, the build block, the _pick lines and the
# explicit make targets. There is a fifth: the depends= array of a DIFFERENT
# sub-package.
#
# It is the only one that fails silently. --nodeps means makepkg never checks,
# so the build succeeds and the package goes into the repository declaring a
# dependency on something this architecture will never produce. Nothing says a
# word until an install is attempted, which for a bootstrap is much later:
#
#   :: unable to satisfy dependency 'libhwasan' required by gcc-libs
#
# This was already paid for once. A previous pass hit it with libquadmath and
# pruned that one name by hand; libhwasan was added to the drop set afterwards
# and the pruning was not extended, so gcc-libs shipped uninstallable. Pruning
# one name at a time is the bug, not the missing name.
#
# So the same `drop` set that decides what is NOT built now also decides what
# is not depended on, and the check below asserts it rather than trusting it.
# Adding a name to that set is now enough, in one place.
#
# libisl.so is in the same list for a DIFFERENT reason, and the difference is
# worth a sentence. The others are components this PKGBUILD stops building.
# isl is an outside library that gcc simply never linked: the host has no isl,
# so configure recorded ISLLIBS='' and ISLINC='', and the artefact agrees --
#
#   $ readelf -d usr/bin/gcc usr/lib/libgcc_s.so.1 | grep -c libisl
#   0
#
# The remedy is the same, so the list is the same. Building isl instead was
# the first plan and it does not work: the Arch packaging repo for isl was
# last touched in 2017 and its only source URL is isl.gforge.inria.fr, which
# died with INRIA's GForge. What this costs is Graphite -- the -floop-*
# optimisations -- and TODO.md records it.
#
# Both spellings occur: a bare name in a sub-package's depends, and the
# versioned "libhwasan=$pkgver-$pkgrel" form in gcc's own. The unused
# package_libhwasan() function can stay -- makepkg never calls a function
# whose name is absent from pkgname.
python3 - <<'PY'
import io, re
drop = ["libhwasan", "libquadmath", "lib32-gcc-libs",
        "libgm2", "libgo", "libgphobos", "libgcobol",
        # Not a component we dropped -- an EXTERNAL library gcc was never
        # configured against. See the note above the list.
        "libisl.so"]
s = io.open("PKGBUILD", encoding="utf-8").read()

def prune(block):
    out = []
    for ln in block.splitlines(True):
        bare = ln.strip().strip('"\'')
        name = bare.split("=")[0]
        if name in drop and (bare == name or bare.startswith(name + "=")):
            continue
        out.append(ln)
    return "".join(out)

# Every depends array in the file: the top-level one and each sub-package's.
s = re.sub(r"(?<=depends=\()[^)]*(?=\))", lambda m: prune(m.group(0)), s)
io.open("PKGBUILD", "w", encoding="utf-8").write(s)

# Assert, do not hope. Any dropped name still inside a depends array is a
# package we would ship unable to install.
left = []
for m in re.finditer(r"depends=\(([^)]*)\)", s):
    for ln in m.group(1).splitlines():
        bare = ln.strip().strip('"\'').split("=")[0]
        if bare in drop:
            left.append(bare)
assert not left, "gcc: dropped names still depended on: %s" % sorted(set(left))
print("gcc: depends pruned of %d dropped components" % len(drop))
PY

# --with-ld / --with-as: our gcc looked for a Debian-named linker.
#
# Found only by building a chroot from stage 1 and trying to compile in it:
#
#   collect2: fatal error: cannot find 'ld'
#
# THE MESSAGE NAMES THE WRONG FILE. /usr/bin/ld was present and executable,
# ld --version ran as the same user, and PATH contained /usr/bin. strace
# settled it in one line:
#
#   newfstatat("/usr/bin/s390x-linux-gnu-ld") = ENOENT
#
# collect2 was not looking for `ld`. It was looking for
# `s390x-linux-gnu-ld` -- the DEBIAN triplet -- and printing the generic name
# in its error. gcc -dumpmachine says s390x-ibm-linux-gnu, so the prefix is
# not the target either; it is what gcc's configure recorded after finding
# Ubuntu's /usr/bin/s390x-linux-gnu-ld, which that host ships and no Arch
# system ever will.
#
# THE REASON STAGE 1 NEVER NOTICED is that every stage-1 build ran on the
# host, where that file exists. The defect was in the shipped compiler all
# along and only a chroot could see it -- the same lesson as the missing
# dynamic linker, one layer up: sixty-eight successful builds proved nothing
# about whether the compiler works anywhere else.
#
# Absolute paths rather than the canonical triplet, because they are correct
# in BOTH places: /usr/bin/ld is Ubuntu's during stage 1 and ours in the
# chroot and on the target. A triplet-prefixed symlink would have papered
# over it and shipped a gcc that still needs a Debian-named tool.
python3 - <<'PY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()
assert "--with-ld=" not in s, "gcc: linker already pinned, hook ran twice"
# _confflags is an ARRAY, shared by both configure passes -- the compiler and
# libgccjit -- so one insertion covers both, and no line-continuation
# backslash belongs on the new entries.
anchor = "      --with-linker-hash-style=gnu\n"
n = s.count(anchor)
assert n == 1, "gcc: expected one --with-linker-hash-style in _confflags, found %d" % n
s = s.replace(anchor, anchor + "      --with-ld=/usr/bin/ld\n      --with-as=/usr/bin/as\n", 1)
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
print("gcc: ld and as pinned to absolute paths")
PY
grep -q -- '--with-ld=/usr/bin/ld' PKGBUILD || {
    echo "gcc: --with-ld not inserted" >&2; exit 1; }

# libgcc_s.so: the PKGBUILD moves a RELATIVE symlink into a deeper directory.
#
#   /usr/bin/ld: cannot find -lgcc_s: No such file or directory
#
# package_gcc() does, at the end:
#
#   mv -v usr/lib/libgcc_s{,_asneeded}.so $_libdir/
#
# where $_libdir is /usr/lib/gcc/<triplet>/16. The two files are not alike.
# libgcc_s_asneeded.so is a linker SCRIPT -- `INPUT ( AS_NEEDED ( -lgcc_s ) )`
# -- so it survives being moved anywhere. libgcc_s.so is a SYMLINK whose
# target is the bare name `libgcc_s.so.1`, i.e. the same directory. That was
# true in /usr/lib, where libgcc_s.so.1 lives; three directories deeper it
# points at nothing.
#
# So -lgcc_s cannot resolve: the only libgcc_s.so on the system is a dangling
# link, and the asneeded script that ld reads instead asks for -lgcc_s again.
# Nothing links, including the trivial `int main(void){return 0;}`.
#
# WHY NOTHING CAUGHT THIS EARLIER, and it is the same reason as the linker
# lookup above: stage 1 compiles with UBUNTU's gcc. Our gcc package was built
# a dozen times and never once used to compile anything. The first program it
# was ever asked to link was in the stage-2 chroot.
#
# The link is repointed rather than the mv removed, because $_libdir is where
# gcc's own search path expects it -- that part of the PKGBUILD is right.
# Three levels up from /usr/lib/gcc/<triplet>/16 is /usr/lib.
python3 - <<'PY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()
old = '    mv -v usr/lib/libgcc_s{,_asneeded}.so $_libdir/\n'
assert s.count(old) == 1, "gcc: libgcc_s move not in the expected form"
fix = old + (
    '    # The moved symlink named its target relative to /usr/lib; from\n'
    '    # $_libdir that resolves to nothing. Repoint it, or -lgcc_s cannot\n'
    '    # be satisfied and the compiler links nothing at all.\n'
    '    ln -sfv ../../../libgcc_s.so.1 $_libdir/libgcc_s.so\n')
s = s.replace(old, fix, 1)
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
PY
grep -qF 'ln -sfv ../../../libgcc_s.so.1' PKGBUILD || {
    echo "gcc: libgcc_s.so link not repointed" >&2; exit 1; }
echo "gcc: libgcc_s.so repointed to ../../../libgcc_s.so.1"

# --- the baseline CPU of the compiler we SHIP ---------------------------------
#
# Arch's PKGBUILD names no s390x baseline, because Arch has no s390x. GCC's own
# fallback for this target is arch5 -- z900, from the year 2000 -- and that is
# what our gcc defaulted to while the host's Ubuntu gcc is configured
# --with-arch=z13 --with-tune=z16. The consequence was not a warning:
#
#   contrib/crc32vx/crc32_vx.c:205:10: error:
#     '__builtin_s390_vec_unpackl' requires '-mvx'
#
# zlib's configure had detected vector support and defined -DHAVE_S390X_VX,
# then compiled with a compiler told to assume a machine that has none.
#
# build-stage2.sh sets the same pair in the chroot's makepkg.conf, which governs
# how this distribution is COMPILED. This governs what the compiler we HAND OVER
# assumes when someone builds on the target with no flags at all. Doing only the
# first leaves a gcc that silently goes back to 2000.
#
# z13 because that is what the host distribution already requires: adopting it
# cannot stop anything from running that runs today.
python3 - <<'ZZPY'
import io, re
lines = io.open("PKGBUILD", encoding="utf-8").read().split("\n")
hit = [i for i, l in enumerate(lines) if "--enable-languages=" in l and "jit" not in l]
assert len(hit) == 1, "gcc: expected one main --enable-languages line, got %d" % len(hit)
i = hit[0]
indent = re.match(r"^[ \t]*", lines[i]).group(0)
assert lines[i].rstrip().endswith("\\"), "gcc: --enable-languages does not continue"
lines.insert(i + 1, indent + "--with-arch=z13 --with-tune=z16 \\")
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lines))
ZZPY
grep -q -- '--with-arch=z13' PKGBUILD || { echo "gcc: baseline not set" >&2; exit 1; }
# On the configure line, not merely in the file.
#
# The first version of this check anchored on --enable-languages=ada and failed
# on a PKGBUILD that was correctly patched: a section ABOVE has already
# rewritten the language list, so `ada` is gone by the time this runs. The
# guard was testing its own stale assumption about the file rather than the
# edit -- the fourth time in this port that a check has verified something
# adjacent to what it meant. Anchor on what the python actually matched.
grep -A1 -E -- '--enable-languages=' PKGBUILD | grep -q -- '--with-arch=z13' || {
    echo "gcc: --with-arch is in the file but not on the configure line" >&2; exit 1; }
echo "gcc: baseline z13, tune z16"
