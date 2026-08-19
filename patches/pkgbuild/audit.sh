#!/usr/bin/env bash
# audit: the python-audit sub-package cannot work, whatever it costs.
#
# The wheel is built by the HOST's python 3.13 and carries a cpython-313 ABI
# tag; Arch ships python 3.14. No destination makes it importable on the
# target -- the same reason python-brotli and python-libseccomp were dropped.
# Stage 2 builds it against the port's own python, where the tag matches.
#
# THE COST ARGUMENT IS NOT THE REASON, and that distinction is worth keeping.
# python-brotli was dropped when the repository held forty packages and
# `python` dragged libffi, mpdecimal and gdbm in behind it. Measured again at
# 131 packages, python costs three: the closure had filled in around it. So
# the cheap-versus-expensive reasoning that was right then is wrong now, and
# reusing it here would have been reasoning from a stale measurement.
#
# What has not changed is the ABI. That is why this one goes.
#
# build() still builds the wheel -- one function for every sub-package -- and
# the result is simply not packaged. package_python-audit() stays in the file,
# uncalled, like package_libquadmath() in gcc.
set -euo pipefail
python3 - <<'PY'
import io, re, sys
s = io.open("PKGBUILD", encoding="utf-8").read()
m = re.search(r"pkgname=\((.*?)\)\n", s, re.S)
assert m, "audit: pkgname array not found"
names = re.findall(r"[A-Za-z0-9._+-]+", m.group(1))
assert "python-audit" in names, "audit: python-audit not in pkgname, found %s" % names
kept = [n for n in names if n != "python-audit"]
s = s[:m.start()] + "pkgname=(\n" + "".join("  %s\n" % n for n in kept) + ")\n" + s[m.end():]
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
PY
python3 - <<'PY'
import io, re, sys
s = io.open("PKGBUILD", encoding="utf-8").read()
m = re.search(r"pkgname=\((.*?)\)\n", s, re.S)
if not m:
    sys.exit("audit: pkgname array unreadable after patching")
names = re.findall(r"[A-Za-z0-9._+-]+", m.group(1))
if "python-audit" in names:
    sys.exit("audit: python-audit still declared in pkgname")
print("audit: pkgname -> %s" % " ".join(names))
PY
echo "audit: python-audit dropped (cp313 wheel, Arch ships python 3.14)"
