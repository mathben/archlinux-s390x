#!/usr/bin/env bash
# qpdf: no manual, and so no qpdf-docs package.
#
# THE DOCUMENTATION PATTERN, twentieth appearance and the most expensive one
# yet. -D BUILD_DOC:BOOL=ON asks for python-sphinx AND python-sphinx_rtd_theme
# AND texlive-bin, texlive-binextra, texlive-fontsrecommended and
# texlive-latexextra -- a Sphinx tree and a TeX distribution, to render a PDF
# manual for a library that this port wants for exactly one reason: pikepdf
# stops on
#
#   pikepdf.h:24:10: fatal error: qpdf/Constants.h: No such file or directory
#
# and pikepdf is what Odoo uses to manipulate PDFs.
#
# AND THE CONSUMER GOES WITH THE PRODUCER. package_qpdf-docs() copies
# build/manual/doc-dist/manual-single-page-html and installs qpdf-manual.pdf,
# both of which only BUILD_DOC produces. Dropping the flag and keeping the
# package would fail on cp, so qpdf-docs leaves pkgname. package_qpdf() needs
# no change: its `rm -rf usr/share/doc` was already tolerant.
set -euo pipefail
python3 - <<'ZZPY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()

old = "-D BUILD_DOC:BOOL=ON"
assert s.count(old) == 1, "qpdf: expected one BUILD_DOC, got %d" % s.count(old)
s = s.replace(old, "-D BUILD_DOC:BOOL=OFF", 1)

old = "pkgname=('qpdf' 'qpdf-docs')"
assert s.count(old) == 1, "qpdf: pkgname line not as expected"
s = s.replace(old, "pkgname=('qpdf')", 1)

io.open("PKGBUILD", "w", encoding="utf-8").write(s)
ZZPY
grep -q -- "-D BUILD_DOC:BOOL=OFF" PKGBUILD || { echo "qpdf: doc build not disabled" >&2; exit 1; }
grep -q "qpdf-docs" <<< "$(sed -n '/^pkgname=/p' PKGBUILD)" && { echo "qpdf: qpdf-docs is still a package" >&2; exit 1; }
grep -qE "rm -rf .*usr/share/doc" PKGBUILD || { echo "qpdf: the doc cleanup is no longer tolerant" >&2; exit 1; }
echo "qpdf: manual disabled, qpdf-docs dropped"
