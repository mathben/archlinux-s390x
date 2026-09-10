#!/usr/bin/env bash
# python-pygments: no HTML documentation.
#
# `make -C doc html` calls sphinx-build, and python-sphinx is the tree this
# port has refused since llvm -- twenty-odd packages so that a syntax
# highlighter ships a manual.
#
# AND ITS CONSUMER GOES WITH IT. package() copies doc/_build/html into
# /usr/share/doc; removing the build alone leaves that copy pointing at a
# directory that no longer exists:
#
#   cp: cannot stat 'doc/_build/html': No such file or directory
#
# That is the shape this port has met twenty times -- htmldocs in linux, the
# docs split in libxml2, groff's lists -- and it is still the easiest one to
# get wrong: the thing removed is not where the failure appears.
#
# The man page and the bash completion STAY: they are shipped in the source
# tree, not produced by sphinx, and dropping them would be removing content
# rather than work.
#
# WHY pygments AT ALL. cython declares it, and cython is in the repository; a
# dependency no package provides is what stage 3 exposed across five names.
set -euo pipefail
python3 - <<'ZZPY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()

old = """  python -m build --wheel --no-isolation
  make -C doc html"""
new = """  python -m build --wheel --no-isolation"""
assert s.count(old) == 1, "pygments: bloc build introuvable"
s = s.replace(old, new, 1)

old = """  mkdir -vp "$pkgdir/usr/share/doc"
  cp -vrT doc/_build/html "$pkgdir/usr/share/doc/$pkgname"
"""
assert s.count(old) == 1, "pygments: copie de la doc introuvable"
s = s.replace(old, "", 1)

old = "  'python-sphinx'\n"
assert s.count(old) == 1, "pygments: makedepend sphinx introuvable"
s = s.replace(old, "", 1)

old = "  'python-wcag-contrast-ratio'\n"
assert s.count(old) == 1, "pygments: makedepend wcag introuvable"
s = s.replace(old, "", 1)

io.open("PKGBUILD", "w", encoding="utf-8").write(s)
ZZPY
grep -qE "^\s*make -C doc html" PKGBUILD && { echo "pygments: la doc survit" >&2; exit 1; }
grep -q "doc/_build" PKGBUILD && { echo "pygments: un consommateur de la doc survit" >&2; exit 1; }
grep -q "python-sphinx" PKGBUILD && { echo "pygments: sphinx survit" >&2; exit 1; }
grep -q "python -m build" PKGBUILD || { echo "pygments: la roue ne se batit plus" >&2; exit 1; }
grep -q "pygmentize.1" PKGBUILD || { echo "pygments: la page de man a disparu" >&2; exit 1; }
echo "pygments: doc html retiree, page de man gardee"
