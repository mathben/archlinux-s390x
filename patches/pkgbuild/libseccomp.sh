#!/usr/bin/env bash
# libseccomp: the python sub-package ships into /usr/local.
#
#   usr/local/lib/python3.13/dist-packages/...
#
# Debian patches sysconfig to prefer its posix_local scheme, so
# `python -m installer` puts the wheel under /usr/local -- a tree an Arch
# package may not ship at all. Nothing fails: makepkg exits 0 and the audit
# is what notices.
#
# THE SAME DECISION AS python-brotli, for the same measured reason. Nothing in
# the repository depends on python-libseccomp -- checked across all 135
# packages -- and keeping it would pull `python` back into the closure, with
# libffi, mpdecimal and gdbm behind it. That closure was deliberately removed
# when python-brotli was dropped; re-admitting it for a binding no package
# asks for would undo the measurement.
#
# And the module would not work anyway: the wheel is built by the host's
# python 3.13 and ABI-tagged cpython-313, while Arch ships 3.14. Stage 2 is
# what produces a usable one.
#
# build() still builds the wheel -- it is one function for both sub-packages
# -- and the result is simply not packaged. package_python-libseccomp() stays
# in the file, uncalled, like package_libquadmath() in gcc.
set -euo pipefail
python3 - <<'PY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()
old = "pkgname=(libseccomp python-libseccomp)"
assert s.count(old) == 1, "libseccomp: pkgname line not in the expected form"
s = s.replace(old, "pkgname=(libseccomp)", 1)
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
PY
grep -q '^pkgname=(libseccomp)$' PKGBUILD || {
    echo "libseccomp: python sub-package not dropped" >&2; exit 1; }
echo "libseccomp: python-libseccomp dropped (would re-admit the python closure)"
