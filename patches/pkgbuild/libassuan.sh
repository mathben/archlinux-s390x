#!/usr/bin/env bash
# libassuan: fetch from the GitHub mirror instead of dev.gnupg.org.
#
#   fatal: unable to access 'https://dev.gnupg.org/source/libassuan.git/'
#
# This is NOT a port problem. dev.gnupg.org is simply unreachable from this
# build host -- measured: HTTP 000, while github.com/gpg/libassuan.git and
# gnupg.org/ftp both answer. The GnuPG project publishes the same history to
# GitHub, so the mirror is the upstream content, not a third-party copy.
#
# The commit the PKGBUILD pins is untouched: only the transport changes, so
# what gets built is bit-for-bit what Arch specifies.
set -euo pipefail
sed -i 's|https://dev\.gnupg\.org/source/libassuan\.git|https://github.com/gpg/libassuan.git|' PKGBUILD
grep -q 'dev.gnupg.org' PKGBUILD && { echo "libassuan: dev.gnupg.org still referenced" >&2; exit 1; }
grep -m1 'github.com/gpg/libassuan' PKGBUILD | sed 's/^\s*//'
echo "libassuan: source switched to the GitHub mirror (dev.gnupg.org unreachable here)"
