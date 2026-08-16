#!/usr/bin/env bash
# curl: disable HTTP/3.
#
#   configure: error: nghttp3 enabled without a QUIC library; enable ngtcp2
#
# Arch builds curl with HTTP/3 through nghttp3 + ngtcp2. Ubuntu packages
# neither, so the build host cannot satisfy them, and building both from
# source to reach HTTP/3 is a detour: nothing in the bootstrap needs it.
# pacman talks to plain HTTPS mirrors, and so does ERPLibre.
#
# DEFERRED, not rejected -- see TODO.md. Re-enable by building ngtcp2 and
# nghttp3 as Arch packages first, then dropping this hook.
set -euo pipefail

# The configure flags.
sed -i 's/--with-nghttp3/--without-nghttp3/; s/--with-ngtcp2/--without-ngtcp2/' PKGBUILD

# The dependency declarations and the soname map. Left in place, the package
# would claim to need libraries it no longer links, and makepkg resolves
# those sonames against the built binary.
sed -i "/'libnghttp3'/d; /'libngtcp2'/d" PKGBUILD

if grep -qE '\-\-with-(nghttp3|ngtcp2)' PKGBUILD; then
    echo "curl: an HTTP/3 library is still requested" >&2; exit 1
fi
if grep -qE "'(libnghttp3|libngtcp2)'" PKGBUILD; then
    echo "curl: an HTTP/3 dependency is still declared" >&2; exit 1
fi
echo "curl: HTTP/3 disabled (no ngtcp2 on the build host)"
