#!/usr/bin/env bash
# llvm: no Sphinx documentation.
#
# -DLLVM_ENABLE_SPHINX=ON pulls in python-sphinx and python-myst-parser, and
# behind those sit docutils, babel, pygments, snowballstemmer, imagesize,
# alabaster, the sphinxcontrib-* family, markdown-it-py and mdit-py-plugins --
# fifteen or so packages whose entire purpose here would be to render HTML for a
# compiler nothing in this port reads the manual of.
#
# MEASURED BEFORE CHOOSING, the way glib2 and iproute2 were: llvm and clang need
# only libedit and python-psutil beyond what this port already has. Sphinx is the
# whole of the rest of the bill, and one flag removes it.
#
# AND THE CLEANUP, found before it failed. package() ends on
#
#   rm -r "$pkgdir"/usr/share/doc/.../html/{_sources,.buildinfo}
#
# which Sphinx creates and which will not exist. This is the seventeenth
# appearance of that shape in this port; the procedure written in jsoncpp's hook
# says to grep package() for the OUTPUT paths after disabling a documentation
# build, and this is the first time it was done before the build rather than
# after. rm -rf rather than deleted: on a machine with Sphinx the directory is
# real and still has to go.
set -euo pipefail
python3 - <<'ZZPY'
import io, re
s = io.open("PKGBUILD", encoding="utf-8").read()
old = "-DLLVM_ENABLE_SPHINX=ON"
assert s.count(old) == 1, "llvm: expected one LLVM_ENABLE_SPHINX, got %d" % s.count(old)
s = s.replace(old, "-DLLVM_ENABLE_SPHINX=OFF", 1)
lines = s.split("\n")
hit = [i for i, l in enumerate(lines) if "_sources" in l and l.lstrip().startswith("rm ")]
assert len(hit) == 1, "llvm: expected one _sources removal, got %d" % len(hit)
lines[hit[0]] = lines[hit[0]].replace("rm -r ", "rm -rf ", 1)
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lines))
ZZPY
grep -q -- "-DLLVM_ENABLE_SPHINX=OFF" PKGBUILD || { echo "llvm: sphinx not disabled" >&2; exit 1; }
grep -qE "^[[:space:]]*rm -rf .*_sources" PKGBUILD || { echo "llvm: the cleanup is not tolerant" >&2; exit 1; }
echo "llvm: Sphinx documentation disabled, cleanup made tolerant"
