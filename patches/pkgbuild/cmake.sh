#!/usr/bin/env bash
# cmake: --qt-gui, on a machine with no display and no Qt.
#
#   CMake Error at Source/QtDialog/CMakeLists.txt:33 (message):
#   Error when bootstrapping CMake:
#
# cmake-gui is a Qt application. Arch lists qt6-base in makedepends and builds
# it; this port has no Qt and will not grow one to give a bootstrap a dialog
# box. Same reasoning as pinentry's Qt front end, and the cost is the same
# thing: a graphical program nothing here can display.
#
# WHY cmake IS IN STAGE 1 AT ALL, since it is worth being clear that this is
# not scope creep: four PKGBUILDs call cmake directly, and stage 2 rebuilds
# every package inside a chroot that has to contain the build systems. cmake
# is a tool the REBUILD needs, not a dependency of anything in the repository
# -- which is why the dependency resolver never asked for it.
#
# --sphinx-man and --sphinx-html stay: sphinx-build is installed, and the man
# pages are worth having.
#
# The makedepends entry goes with the flag. Nothing checks it under --nodeps,
# but a package declaring a build dependency it does not use is the same
# untruth as gcc-libs declaring libhwasan -- and leaving it would tell the
# next reader that Qt was needed here.
set -euo pipefail
python3 - <<'ZZPY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()

old = "    --qt-gui \\\n"
assert s.count(old) == 1, "cmake: expected exactly one --qt-gui"
s = s.replace(old, "", 1)

old = "             qt6-base)"
assert s.count(old) == 1, "cmake: makedepends tail not in the expected form"
s = s.replace(old, "             )", 1)

io.open("PKGBUILD", "w", encoding="utf-8").write(s)
ZZPY
grep -q -- '--qt-gui' PKGBUILD && { echo "cmake: --qt-gui survived" >&2; exit 1; }
sed -n '/^makedepends=(/,/)/p' PKGBUILD | grep -q 'qt6-base' && {
    echo "cmake: qt6-base still in makedepends" >&2; exit 1; }
grep -q -- '--sphinx-man' PKGBUILD || {
    echo "cmake: man pages lost with the GUI" >&2; exit 1; }
echo "cmake: --qt-gui dropped (no Qt, no display)"

# emacs, for one lisp file, at the very last line of package().
#
#   PKGBUILD: line 64: emacs: command not found
#
# The build compiled everything, generated the sphinx documentation, installed
# the whole tree, and then died on
#
#   emacs -batch -f batch-byte-compile .../site-lisp/cmake-mode.el
#
# make install already put cmake-mode.el in place; this only produces the
# byte-compiled .elc beside it. Emacs loads the .el perfectly well without it,
# a little slower on first load. Installing emacs -- forty megabytes and its
# own dependency tree -- to pre-compile one editor mode for a bootstrap that
# has no editor is not a trade worth making.
#
# THE SHAPE IS WORTH NOTING because it is the third time: pam's PDF removal,
# e2fsprogs' fuse2fs removal, and now this. A failure on the LAST line of
# package(), after a completely successful build, always looks like something
# broke badly. It never is -- it is a tool the host does not have, doing
# something optional.
set -euo pipefail
python3 - <<'ZZPY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()
old = '  emacs -batch -f batch-byte-compile "${pkgdir}"/usr/share/emacs/site-lisp/cmake-mode.el\n'
assert s.count(old) == 1, "cmake: the emacs byte-compile line is not in the expected form"
s = s.replace(old, "", 1)
old = "makedepends=(emacs\n"
assert s.count(old) == 1, "cmake: makedepends does not start with emacs"
s = s.replace(old, "makedepends=(\n", 1)
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
ZZPY
grep -q 'emacs -batch' PKGBUILD && { echo "cmake: the emacs step survived" >&2; exit 1; }
sed -n '/^makedepends=(/,/)/p' PKGBUILD | grep -qw emacs && {
    echo "cmake: emacs still in makedepends" >&2; exit 1; }
grep -q 'cmake-mode' PKGBUILD && {
    echo "cmake: a cmake-mode reference remains -- check it is harmless" >&2; }
echo "cmake: emacs byte-compilation dropped (the .el is installed regardless)"

# --- no Sphinx documentation ---------------------------------------------------
#
#   CMake Error at Utilities/Sphinx/CMakeLists.txt:52 (message):
#
# cmake builds its own manual and man pages with Sphinx, requested by
# --sphinx-man and --sphinx-html in the bootstrap arguments. python-sphinx is not
# in this port: it is a large Python documentation stack, and cmake is wanted here
# as a build tool.
#
# BOTH FLAGS, and they are bootstrap arguments rather than -D options -- cmake
# configures itself with its own script before it can run itself. Dropping only
# one leaves the other pulling Sphinx in, and the error is identical, which is how
# a half-fix looks like no fix.
set -euo pipefail
python3 - <<'ZZPY'
import io, re
lines = io.open("PKGBUILD", encoding="utf-8").read().split("\n")
hit = [i for i, l in enumerate(lines) if re.match(r"^[ \t]*--sphinx-(man|html)[ \t]*\\\\?$", l)]
assert len(hit) == 2, "cmake: expected two --sphinx flags, got %d" % len(hit)
# Backwards: deleting shifts everything after it.
for i in reversed(hit):
    del lines[i]
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lines))
ZZPY
grep -qE "^[[:space:]]*--sphinx-" PKGBUILD && {
    echo "cmake: a --sphinx flag survived" >&2; exit 1; }
echo "cmake: Sphinx manual and man pages dropped"

# --- and the html it no longer generates --------------------------------------
#
#   rm: cannot remove '<pkgdir>/usr/share/doc/cmake/html/_sources': No such file
#
# ELEVENTH time in this port. With Sphinx off, cmake generates no html, and the
# PKGBUILD deletes _sources from it -- Sphinx leaves the reStructuredText inputs
# beside the rendered pages and they are not wanted in a package.
#
# rm -rf rather than deleted: on a machine with Sphinx the directory is real and
# still has to go.
python3 - <<'ZZPY'
import io, re
lines = io.open("PKGBUILD", encoding="utf-8").read().split("\n")
hit = [i for i, l in enumerate(lines) if "_sources" in l and l.lstrip().startswith("rm ")]
assert len(hit) == 1, "cmake: expected one _sources removal, got %d" % len(hit)
i = hit[0]
lines[i] = lines[i].replace("rm -r ", "rm -rf ", 1)
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lines))
ZZPY
grep -qE "^[[:space:]]*rm -rf .*_sources" PKGBUILD || {
    echo "cmake: the _sources removal was not made tolerant" >&2; exit 1; }
echo "cmake: _sources cleanup tolerates its absence"
