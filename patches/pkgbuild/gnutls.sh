#!/usr/bin/env bash
# gnutls: leancrypto is asked for, and Ubuntu has no such library.
#
#   configure: error: leancrypto support was requested but the required
#                     libraries were not found.
#
# Arch packages leancrypto -- a post-quantum crypto library -- and gnutls
# links it for ML-KEM and ML-DSA. Nothing about s390x prevents it; the build
# host simply cannot supply it, and building leancrypto first would add a
# package to the closure for algorithms pacman does not use. It signs with
# OpenPGP through gpgme, and TLS to the mirrors needs none of this.
#
# TWO PLACES, and the second is the one that bites silently. The configure
# flag is what stops the build, so it is what gets noticed. But 'leancrypto'
# is ALSO in depends=, and --nodeps means makepkg never checks it: gnutls
# would build, pass, and enter the repository asking for a package this port
# will never contain. Same shape as gcc-libs declaring libhwasan, and as make
# declaring guile -- the third instance of it in this port, which is why the
# audit that finds them is now part of the routine rather than an afterthought.
set -euo pipefail
python3 - <<'PY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()

# (a) the flag that stops configure. It is the LAST option on the line, with
#     no trailing backslash, so the preceding backslash goes with it.
old = " \\\n    --with-leancrypto"
assert s.count(old) == 1, "gnutls: expected exactly one --with-leancrypto"
s = s.replace(old, "", 1)

# (b) the declaration nobody checks
old = "'leancrypto' "
assert s.count(old) == 1, "gnutls: expected exactly one leancrypto in depends"
s = s.replace(old, "", 1)

io.open("PKGBUILD", "w", encoding="utf-8").write(s)
PY
grep -q 'leancrypto' PKGBUILD && {
    echo "gnutls: leancrypto still referenced" >&2; exit 1; }
echo "gnutls: leancrypto dropped from configure AND from depends"
