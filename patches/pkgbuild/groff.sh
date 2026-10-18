#!/usr/bin/env bash
# groff: one decorative figure, and no netpbm to draw it.
#
#   program 'xpmtoppm' is missing; can't generate doc/gnu.eps
#   make[2]: *** [Makefile:19801: doc/gnu.eps] Error 1
#
# xpmtoppm belongs to netpbm. What it produces is the GNU logo, as EPS, for
# groff's own manual -- and getting it would mean packaging netpbm and the image
# libraries under it (libjpeg-turbo, libpng, libtiff, jbigkit), none of which
# anything else in this bootstrap wants.
#
# NO CONFIGURE SWITCH EXISTS: groff's configure has neither --without-doc nor
# --disable-doc, so there was nothing to turn off. Adding an invented flag would
# have been worse than useless -- autoconf merely warns about options it does not
# know, the build would have failed identically, and the hook's own check would
# have passed.
#
# The Makefile is generated, so it is edited after configure and before make. The
# variable is emptied rather than the rule patched, because the INSTALL side is
# already tolerant:
#
#   if test -f "$$d/gnu.eps"; then ... fi
#
# so with nothing built, nothing is installed and nothing complains. One line,
# and the only one whose absence the rest of the Makefile already handles.
set -euo pipefail
python3 - <<'ZZPY'
import io, re
lines = io.open("PKGBUILD", encoding="utf-8").read().split("\n")
mk = [i for i, l in enumerate(lines) if re.match(r"^[ \t]*make[ \t]*$", l)]
assert len(mk) >= 1, "groff: no bare `make` line found in build()"
i = mk[0]
ind = re.match(r"^[ \t]*", lines[i]).group(0)
lines[i:i] = [
    ind + "# doc/gnu.eps needs xpmtoppm from netpbm, which this port does not",
    ind + "# package. The install side already skips the file when it is absent.",
    ind + 'sed -i "s|^DOC_GNU_EPS = doc/gnu.eps$|DOC_GNU_EPS =|" Makefile',
    ind + 'grep -q "^DOC_GNU_EPS =$" Makefile',
    ind + "# And its CONSUMER. Emptying DOC_GNU_EPS removed the rule that",
    ind + "# builds the figure and not the document that includes it:",
    ind + "#",
    ind + "#   doc/webpage.ms:45: error: cannot open 'gnu.eps'",
    ind + "#   doc/webpage.ms:45: fatal error: PSPIC failed to include 'gnu.eps'",
    ind + "#",
    ind + "# PROCESSEDEXAMPLEFILES_PS lists webpage.ps and grnexmpl.ps, and",
    ind + "# PROCESSEDEXAMPLEFILES_HTML lists webpage.html. Which members exist",
    ind + "# depends on what configure found: it empties the list for an output",
    ind + "# driver whose helper tools are missing, so a host carrying netpbm",
    ind + "# and ghostscript keeps the HTML one and renders the same document",
    ind + "# that needs the figure. Treating any member as reliably empty is how",
    ind + "# the HTML one slipped through, and the build stops on",
    ind + "#",
    ind + "#   doc/webpage.ms:45: fatal error: PSPIC failed to include 'gnu.eps'",
    ind + "#",
    ind + "# so the family is DISCOVERED below, alongside PROCESSEDDOCFILES.",
    ind + "# THE SECOND consumer. Two files include the logo, and only two --",
    ind + "# counted rather than guessed:",
    ind + "#",
    ind + "#   doc/webpage.ms                             (above)",
    ind + "#   contrib/hdtbl/examples/mixed_pickles.roff  (this)",
    ind + "#",
    ind + "# hdtbl renders its example tables to PostScript, and one of them shows",
    ind + "# the GNU logo. HDTBLPROCESSEDEXAMPLEFILES lists all twelve; the whole",
    ind + "# list goes, because there is no reason to render eleven examples of a",
    ind + "# table macro package into a documentation set nothing here reads.",
    ind + "# ALL of them, not one per failure. This is the third round on the",
    ind + "# same package: DOC_GNU_EPS, then PROCESSEDEXAMPLEFILES_PS, then",
    ind + "# HDTBL, and mom's examples were waiting behind those --",
    ind + "#",
    ind + "#   pdfmom: fatal error: test-groff exited with status 4",
    ind + "#   contrib/mom/examples/typesetting.pdf",
    ind + "#",
    ind + "# groff renders its own manuals and every contrib package's examples",
    ind + "# to PostScript and PDF using the groff being built. Each list is a",
    ind + "# separate variable, and finding them one failure at a time is how",
    ind + "# three passes went by. They are emptied together.",
    ind + "# three passes went by. The PROCESSEDDOCFILES family is DISCOVERED",
    ind + "# rather than listed: upstream added PROCESSEDDOCFILES_HTML after",
    ind + "# this hook was written, and a fixed list meets a new member one",
    ind + "# failed build at a time. Closing the family costs one grep.",
    ind + '_lists="HDTBLPROCESSEDEXAMPLEFILES MOMPROCESSEDEXAMPLEFILES GENERATEDDOCFILES"',
    ind + '_lists="$_lists $(grep -oE \'^PROCESSED(DOC|EXAMPLE)FILES[A-Z_]*\' Makefile | sort -u)"',
    ind + 'for _v in $_lists; do',
    ind + '  sed -i "/^$_v = /,/^$/ s|^.*$||" Makefile',
    ind + '  grep -q "^$_v *=" Makefile && { echo "groff: $_v not emptied" >&2; exit 1; }',
    ind + 'done',
    ind + '# The sweep that would have caught the HTML list on its first day.',
    ind + 'grep -qE "^PROCESSED(DOC|EXAMPLE)FILES[A-Z_]* *=" Makefile && {',
    ind + '  echo "groff: a PROCESSED*FILES variable survived the sweep" >&2; exit 1; }',
    ind + "# AND THE INSTALL SIDE, which must be disarmed at the RULE and never",
    ind + "# at the variable. Emptying the lists that RENDER the HTML",
    ind + "# documentation leaves the rules that INSTALL it, and those are",
    ind + "#",
    ind + "#   for f in `ls $(HTMLDOCFILESALL)`",
    ind + "#",
    ind + "# where an empty list makes ls read the CURRENT DIRECTORY and the",
    ind + "# loop install everything in it, directories included:",
    ind + "#",
    ind + "#   install: omitting directory 'groff.dvi.t2d'",
    ind + "#",
    ind + "# Their companion lines are $(RM) dir/$(VAR), which with an empty",
    ind + "# VAR removes the directory itself. So the RECIPES go, and the",
    ind + "# variables keep their values. The targets are found by the shape",
    ind + "# that makes them dangerous rather than by name.",
    ind + '_tgts="$(awk \'/^[A-Za-z_][A-Za-z0-9_.-]*:/ { t = $0; sub(/:.*/, "", t) } /`ls [$][(]HTML/ && t != "" { print t }\' Makefile | sort -u)"',
    ind + '[ -n "$_tgts" ] || { echo "groff: no install rule consumes an HTML list" >&2; exit 1; }',
    ind + 'for _t in $_tgts; do',
    ind + '  awk -v t="$_t" \'BEGIN { d = 0 } $0 ~ "^" t ":" { print; d = 1; next } d && /^\\t/ { next } { d = 0; print }\' Makefile > Makefile.new',
    ind + '  mv Makefile.new Makefile',
    ind + '  # Textual, not `make -n`: make refuses to run at all when a',
    ind + '  # prerequisite is missing, so an empty plan would prove nothing.',
    ind + '  awk -v t="$_t" \'$0 ~ "^" t ":" { f = 1; next } f && /^\\t/ { print "x"; exit } f { exit }\' Makefile \\',
    ind + '    | grep -q x && { echo "groff: $_t still has a recipe" >&2; exit 1; }',
    ind + 'done',
    ind + "# And say it out loud: if a THIRD consumer appears, this is the pattern",
    ind + "# to look for, not a new kind of problem.",
    ind + 'if grep -rl "gnu\\.eps" --include="*.roff" --include="*.ms" . 2>/dev/null | grep -qv "^\\./doc/webpage.ms$\\|mixed_pickles"; then',
    ind + '  echo "groff: a third file includes gnu.eps; see patches/pkgbuild/groff.sh" >&2',
    ind + '  exit 1',
    ind + 'fi',
]
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lines))
ZZPY
grep -q "DOC_GNU_EPS" PKGBUILD || { echo "groff: the figure was not dropped" >&2; exit 1; }
# The grep inside build() is the real check: it runs against the generated
# Makefile and fails the build if the variable was not what this hook expects.
grep -q 'grep -q "\^DOC_GNU_EPS =\$" Makefile' PKGBUILD || {
    echo "groff: the in-build verification is missing" >&2; exit 1; }
echo "groff: GNU logo figure dropped, with every list that renders it"
