#!/usr/bin/env bash
# openssl: s390x needs the 64-bit Configure target.
#
# The PKGBUILD composes its target as "linux-$CARCH", which gives
# linux-s390x. That IS a valid OpenSSL target -- it is the 31-bit one. The
# 64-bit target is linux64-s390x, and building 31-bit objects on a 64-bit
# system fails without ever saying so plainly: the log ends on
#
#   Configuring OpenSSL version 3.6.3 for target linux-s390x
#
# and the failure looks like it came from nowhere.
#
# The PKGBUILD already special-cases exactly this for riscv64, so the fix is
# to join that case rather than invent a mechanism.
set -euo pipefail
python3 - <<'PY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()
old = '\t"riscv64")\n'
assert old in s, "riscv64 case not found"
s = s.replace(old, '\t"s390x" | "riscv64")\n', 1)
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
PY
grep -q '"s390x" | "riscv64")' PKGBUILD || { echo "openssl: case not extended" >&2; exit 1; }
echo "openssl: Configure target set to linux64-s390x (linux-s390x is 31-bit)"
