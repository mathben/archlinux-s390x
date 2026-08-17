#!/usr/bin/env bash
# pam: the PDF removal assumes fop, which the Ubuntu host does not have.
#
#   rm: cannot remove
#   '.../pkg/pam/usr/share/doc/Linux-PAM/*.pdf': No such file or directory
#
# package() ends on
#
#   # remove unreproducible pdf files
#   rm "${pkgdir}"/usr/share/doc/Linux-PAM/*.pdf
#
# and that line only works because Arch lists fop in makedepends. fop is a
# Java renderer; putting a JVM on the build host to produce three PDFs that
# the very next line deletes buys nothing, so the host stays without it.
#
# Without fop meson drops every PDF target in silence -- doc/adg, doc/mwg and
# doc/sag each guard theirs with `if prog_fop.found()`, and the configured
# build.ninja then holds zero .pdf rules. The DIRECTORY still exists, because
# the HTML and text manuals install beside them, so the glob is never
# expanded and rm is handed the literal string `*.pdf`. Same shape as the
# util-linux glob that started the libdir hunt: the message names a path that
# was never going to exist, and it aborts package() AFTER a successful
# compile -- so the build looks like it failed at the very last step for no
# reason at all.
#
# -f is the whole fix. With fop the PDFs are still removed; without it the
# empty glob stops being an error.
#
# Not a hook, but the other half of pam and worth finding here: libnsl and
# libtirpc are NOT optional on this host even though upstream marks NIS
# `auto`, because arch-meson passes --auto-features enabled, which promotes
# every auto feature to a hard requirement. Same mechanism turns pam's `docs`
# feature into five fatal xmlcatalog probes. All of it is host packages, and
# they are declared in install_host_deps.
set -euo pipefail
# Exactly one removal, and it must be the pdf one. Never a blanket rewrite:
# package() also runs `install` and `chmod +s` on paths under the same tree,
# and meson install itself writes there.
n=$(grep -cF 'rm "${pkgdir}"/usr/share/doc/Linux-PAM/' PKGBUILD || true)
[ "$n" = "1" ] || { echo "pam: expected 1 pdf removal, found $n" >&2; exit 1; }
sed -i 's|rm "${pkgdir}"/usr/share/doc/Linux-PAM/|rm -f "${pkgdir}"/usr/share/doc/Linux-PAM/|' PKGBUILD
grep -qF 'rm -f "${pkgdir}"/usr/share/doc/Linux-PAM/*.pdf' PKGBUILD || {
    echo "pam: pdf removal not made tolerant" >&2; exit 1; }
echo "pam: pdf removal tolerates the empty glob (host has no fop)"
