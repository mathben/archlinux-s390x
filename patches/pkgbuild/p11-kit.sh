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
