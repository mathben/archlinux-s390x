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

sed -i 's/^\(\s*--enable-languages=\).*\\$/\1c,c++,fortran,lto,objc,obj-c++ \\/' PKGBUILD
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

# Verify what matters: the array makepkg iterates. Grepping the whole file
# for the bare name declared a false failure once already, on libtool and
# then here -- the string survives in comments and in unused functions.
if sed -n '/^pkgname=(/,/^)/p' PKGBUILD | grep -q 'lib32'; then
    echo "gcc: lib32 still in pkgname array" >&2; exit 1
fi
grep -m1 -- '--enable-languages' PKGBUILD
echo "gcc: front ends reduced, multilib off, lib32 removed"
