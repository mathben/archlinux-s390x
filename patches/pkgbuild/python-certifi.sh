#!/usr/bin/env bash
# package() asks the interpreter where packages go, and writes there:
#
#   local site_packages=$(python -c "import site; print(site.getsitepackages()[0])")
#   ln -sf /etc/ssl/certs/ca-certificates.crt "$pkgdir/$site_packages/certifi/cacert.pem"
#
# The two do not have to agree. On a distribution whose site.py puts the local
# directory first, getsitepackages()[0] names /usr/local, while the wheel
# installs into the system path, and ln reports only
#
#   ln: No such file or directory
#
# naming neither the path it tried nor the one that exists. Locating the file
# the wheel actually installed needs no interpreter and is right in any layout.
# The bundled store is replaced by a link to the system one so the package
# follows the host's trust decisions instead of carrying a frozen copy.
set -euo pipefail
python3 - <<'ZZPY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()
old = 'ln -sf /etc/ssl/certs/ca-certificates.crt "$pkgdir/$site_packages/certifi/cacert.pem"'
assert s.count(old) == 1, "certifi: la ligne ln n est pas sous la forme attendue"
new = ('_c=$(find "$pkgdir" -path "*/certifi/cacert.pem" | head -1)\n'
       '  [ -n "$_c" ] || { echo "certifi: cacert.pem introuvable dans $pkgdir" >&2; exit 1; }\n'
       '  ln -sf /etc/ssl/certs/ca-certificates.crt "$_c"')
s = s.replace(old, new, 1)
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
ZZPY
grep -q 'site_packages/certifi/cacert.pem' PKGBUILD && {
    echo "certifi: le chemin devine survit" >&2; exit 1; }
grep -q 'path "\*/certifi/cacert.pem"' PKGBUILD || {
    echo "certifi: la recherche n a pas ete posee" >&2; exit 1; }
echo "python-certifi: cacert.pem localise, pas devine"
