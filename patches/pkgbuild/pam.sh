#!/usr/bin/env bash
# pam: no XML documentation.
#
#   meson.build:42:2: ERROR: Command `/usr/bin/xmllint --nonet --noout ...`
#
# xmllint EXISTS here -- it comes from our libxml2 -- and that is what makes this
# one different from the other documentation failures. It fails because pam
# validates its DocBook sources against DTDs that are not installed, and
# --nonet forbids fetching them. Shipping the DocBook XML data would be a
# package; disabling the documentation is a flag.
set -euo pipefail
python3 - <<'ZZPY'
import io, re
lines = io.open("PKGBUILD", encoding="utf-8").read().split("\n")
hit = [i for i, l in enumerate(lines) if re.search(r"^[ \t]*-Dselinux=disabled", l)]
assert len(hit) == 1, "pam: expected one -Dselinux option line, got %d" % len(hit)
i = hit[0]
ind = re.match(r"^[ \t]*", lines[i]).group(0)
assert lines[i].rstrip().endswith("\\"), "pam: the option list does not continue"
lines.insert(i + 1, ind + "-Ddocs=disabled \\")
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lines))
ZZPY
grep -q -- "-Ddocs=disabled" PKGBUILD || { echo "pam: docs not disabled" >&2; exit 1; }
echo "pam: DocBook documentation disabled"

# --- and the PDFs it no longer produces ---------------------------------------
#
#   rm: cannot remove '<pkgdir>/usr/share/doc/Linux-PAM/*.pdf': No such file
#
# The line above it says why it exists:
#
#   # remove unreproducible pdf files
#
# pam builds PDFs whose bytes differ between runs, so the PKGBUILD deletes them
# to keep the package reproducible. With -Ddocs=disabled they are never built,
# and a cleanup step that finds nothing to clean is fatal under set -e.
#
# The rm becomes tolerant rather than being deleted: on a machine that does have
# the DocBook stack, the PDFs WILL be there and they still have to go.
python3 - <<'ZZPY'
import io, re
lines = io.open("PKGBUILD", encoding="utf-8").read().split("\n")
hit = [i for i, l in enumerate(lines) if re.search(r"\*\.pdf", l) and l.lstrip().startswith("rm ")]
assert len(hit) == 1, "pam: expected one pdf removal, got %d" % len(hit)
i = hit[0]
ind = re.match(r"^[ \t]*", lines[i]).group(0)
lines[i] = ind + "rm -f " + lines[i].lstrip()[3:].lstrip()
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lines))
ZZPY
grep -qE "^[[:space:]]*rm -f .*\*\.pdf" PKGBUILD || {
    echo "pam: the pdf removal was not made tolerant" >&2; exit 1; }
echo "pam: PDF cleanup tolerates their absence"
