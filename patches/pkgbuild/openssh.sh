#!/usr/bin/env bash
# openssh: no FIDO2 security keys.
#
# --with-security-key-builtin wants libfido2, which this port does not build,
# and libfido2 wants libcbor and hidapi behind it. Three packages so that a
# headless s390x guest under QEMU can authenticate with a USB security token it
# has no bus to plug into.
#
# The flag sits alone on its line inside a bash ARRAY, so deleting the line is
# safe. That distinction matters here: in binutils the same instinct broke a
# backslash-continued command, because commenting or deleting a line inside an
# invocation severs the continuation. An array element is not a continuation.
#
# What is lost is exactly ssh-sk-helper and the sk-* key types. Password and
# public-key authentication are untouched, which is all this deployment uses.
set -euo pipefail
python3 - <<'ZZPY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()
lines = s.split("\n")
hit = [i for i, l in enumerate(lines) if l.strip() == "--with-security-key-builtin"]
assert len(hit) == 1, "openssh: expected one security-key flag, got %d" % len(hit)
del lines[hit[0]]
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lines))
ZZPY
grep -q "security-key-builtin" PKGBUILD && { echo "openssh: the FIDO2 flag survived" >&2; exit 1; }
grep -q -- "--with-pam" PKGBUILD || { echo "openssh: deleted too much, --with-pam is gone" >&2; exit 1; }
grep -q -- "--with-libedit" PKGBUILD || { echo "openssh: deleted too much, --with-libedit is gone" >&2; exit 1; }
echo "openssh: FIDO2 security keys disabled"
