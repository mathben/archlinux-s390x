#!/usr/bin/env bash
# p11-kit: no gtk-doc manual.
#
#   meson.build:65:18: ERROR: Dependency "glib-2.0" not found (tried pkgconfig)
#
# THIS ONE WAS NEARLY A SUB-PROJECT. glib-2.0 is not in this port, and adding it
# is not one package: Arch's glib2 wants gobject-introspection (which itself
# needs glib2 -- a cycle to bootstrap), libsysprof-capture, dconf and gi-docgen.
# Several packages and a circular dependency, for one entry in one build.
#
# Reading where the requirement actually comes from changed the answer entirely.
# The file is doc/manual/meson.build, and the line is
#
#   glib_prefix = dependency('glib-2.0').get_variable(pkgconfig : 'prefix')
#
# glib is consulted to find where gtk-doc keeps its cross-reference files. It is
# not linked, not called, and nothing in p11-kit's code touches it. -D gtk_doc
# is already in the PKGBUILD's option list, set to true; turning it false drops
# the whole doc/manual subdirectory and the dependency with it.
#
# The lesson is the one this port keeps relearning: the error names glib, and
# glib is not the subject. Six lines of context said so.
set -euo pipefail
python3 - <<'ZZPY'
import io, re
lines = io.open("PKGBUILD", encoding="utf-8").read().split("\n")
hit = [i for i, l in enumerate(lines) if re.match(r"^[ \t]*-D gtk_doc=true[ \t]*$", l)]
assert len(hit) == 1, "p11-kit: expected one -D gtk_doc=true, got %d" % len(hit)
lines[hit[0]] = lines[hit[0]].replace("gtk_doc=true", "gtk_doc=false")
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lines))
ZZPY
grep -q -- "-D gtk_doc=false" PKGBUILD || { echo "p11-kit: gtk_doc not disabled" >&2; exit 1; }
echo "p11-kit: gtk-doc manual disabled (glib was only locating its xrefs)"

# --- and no man pages either --------------------------------------------------
#
# With gtk_doc off, the next line was
#
#   meson.build:94:4: ERROR: Problem encountered: Docbook stylesheet for man
#   pages not found
#
# The stylesheets, not xsltproc -- which our libxslt supplies. Third package to
# stop on exactly this: pam validates DocBook sources it cannot fetch, shadow
# renders man pages from them. Shipping docbook-xsl would be a package that only
# documentation needs; -D man is already in the option list.
python3 - <<'ZZPY'
import io, re
lines = io.open("PKGBUILD", encoding="utf-8").read().split("\n")
hit = [i for i, l in enumerate(lines) if re.match(r"^[ \t]*-D man=true[ \t]*$", l)]
assert len(hit) == 1, "p11-kit: expected one -D man=true, got %d" % len(hit)
lines[hit[0]] = lines[hit[0]].replace("man=true", "man=false")
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lines))
ZZPY
grep -q -- "-D man=false" PKGBUILD || { echo "p11-kit: man not disabled" >&2; exit 1; }
echo "p11-kit: man pages disabled (DocBook stylesheets absent, not xsltproc)"

# --- and the gtk-doc split ----------------------------------------------------
#
#   mv: cannot stat '<pkgdir>/usr/share/gtk-doc': No such file or directory
#
# TWELFTH time. -D gtk_doc=false above stopped the documentation being built and
# left package() splitting it out:
#
#   _pick doc "$pkgdir"/usr/share/gtk-doc
#
# _pick is Arch's helper for moving a path into a sub-package, and it is as fatal
# on a missing path as a bare mv.
python3 - <<'ZZPY'
import io, re
lines = io.open("PKGBUILD", encoding="utf-8").read().split("\n")
hit = [i for i, l in enumerate(lines) if "gtk-doc" in l and "_pick" in l]
assert len(hit) == 1, "p11-kit: expected one gtk-doc _pick, got %d" % len(hit)
i = hit[0]
ind = re.match(r"^[ \t]*", lines[i]).group(0)
lines[i] = ind + ": # gtk_doc is false above, so usr/share/gtk-doc is never created."
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lines))
ZZPY
grep -qE "_pick doc .*gtk-doc" PKGBUILD && {
    echo "p11-kit: the gtk-doc pick survived" >&2; exit 1; }
echo "p11-kit: gtk-doc split removed (nothing builds it now)"
