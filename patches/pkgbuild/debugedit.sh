#!/usr/bin/env bash
# debugedit: build it without gdb.
#
# configure ABORTS when gdb-add-index is absent -- `AC_MSG_ERROR`, no option to
# say otherwise. Nothing in debugedit itself calls it: the program rewrites
# source paths inside .debug sections, and the missing tool belongs to
# find-debuginfo, a SCRIPT shipped alongside, and only when it builds a gdb
# index. A hard failure for an optional consumer.
#
# WHAT THE ALTERNATIVE COSTS. gdb pulls guile and source-highlight, and
# source-highlight pulls boost. Three heavy trees so that a build machine which
# compiles everything with !debug can index debug packages it never produces.
# Same arithmetic that kept doxygen, asciidoctor and tk out.
#
# SO THE ERROR BECOMES A WARNING, and the dependency goes with it. Arch already
# patches this PKGBUILD to drop dwz for the same reason, one consumer further
# up; prepare() runs autoreconf, so configure.ac is what gets edited, not the
# generated script.
#
# WHAT IS LOST, precisely: find-debuginfo produces debug packages with no gdb
# index. Not slower -- absent. To restore, build gdb and remove this hook.
set -euo pipefail
python3 - <<'ZZPY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()

old = """    patch -Np1 < "$srcdir/remove-dwz.patch"
    autoreconf -fiv"""
new = """    patch -Np1 < "$srcdir/remove-dwz.patch"
    # gdb-add-index is find-debuginfo's, not debugedit's: detect it, do not
    # die of it. See patches/pkgbuild/debugedit.sh for what that costs.
    sed -i 's|AC_MSG_ERROR(\\[gdb-add-index needed by find-debuginfo\\])|AC_MSG_WARN([gdb-add-index absent: debug packages carry no gdb index])|' configure.ac
    grep -q 'AC_MSG_ERROR(\\[gdb-add-index' configure.ac \\
        && { echo 'debugedit: the gdb-add-index abort survived' >&2; exit 1; }
    autoreconf -fiv"""
assert s.count(old) == 1, "debugedit: bloc prepare introuvable"
s = s.replace(old, new, 1)

old = "depends=('glibc' 'libelf' 'xxhash' 'cpio' 'elfutils' 'gdb')"
new = "depends=('glibc' 'libelf' 'xxhash' 'cpio' 'elfutils')"
assert s.count(old) == 1, "debugedit: depends introuvable"
s = s.replace(old, new, 1)

io.open("PKGBUILD", "w", encoding="utf-8").write(s)
ZZPY
grep -q "'gdb'" PKGBUILD && { echo "debugedit: la dependance gdb survit" >&2; exit 1; }
grep -q "AC_MSG_WARN" PKGBUILD || { echo "debugedit: l avertissement n a pas ete pose" >&2; exit 1; }
echo "debugedit: gdb retire, l arret de configure devient un avertissement"
