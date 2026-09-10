#!/usr/bin/env bash
# cython: drop the numpy dependency.
#
# WHY IT IS DECLARED. Cython ships .pxd files that describe numpy's C API, so
# that Cython code which uses numpy arrays can `cimport numpy`. Arch names
# numpy in depends for those users.
#
# WHY IT GOES HERE. Nothing in this port compiles Cython code against numpy --
# the .pxd files stay in the package and are simply never read. What numpy
# costs is not itself: it depends on cblas and lapack, neither of which this
# port builds, and the usual provider of both is a full BLAS implementation.
# Three trees so that a file nobody opens has a library behind it.
#
# python-pygments, the other half of cython's declaration, is NOT removed: it
# is pure Python and it is built. A dependency is dropped because it costs a
# tree, never because it is merely unused.
#
# TO RESTORE: build cblas, lapack and numpy, then delete this hook. Anyone
# compiling numpy-using Cython here will need them anyway, and will find out
# with `cimport numpy` failing rather than with a broken install.
set -euo pipefail
python3 - <<'ZZPY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()

# Le tableau tient sur plusieurs lignes, sans guillemets : la ligne ENTIERE
# part, sinon il reste une indentation orpheline dans le tableau.
old = "         python-numpy\n"
assert s.count(old) == 1, "cython: ligne python-numpy introuvable"
s = s.replace(old, "", 1)

io.open("PKGBUILD", "w", encoding="utf-8").write(s)
ZZPY
grep -q "python-numpy" PKGBUILD && { echo "cython: numpy survit" >&2; exit 1; }
grep -q "python-pygments" PKGBUILD || { echo "cython: pygments a disparu" >&2; exit 1; }
echo "cython: numpy retire, pygments garde"
