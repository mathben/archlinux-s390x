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
for _lang in gcc-ada gcc-d gcc-go gcc-m2 gcc-rust gcc-gcobol \
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
