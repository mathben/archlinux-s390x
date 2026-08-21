#!/usr/bin/env bash
# fakeroot: no translated man pages.
#
#   po4a: command not found
#
# build() ends on a po4a call that renders the man page into every language it
# has a catalogue for. po4a is Perl, and packaging it means packaging its module
# stack -- perl-yaml-tiny, perl-syntax-keyword-try, perl-term-readkey,
# perl-locale-gettext and more -- so that fakeroot's man page exists in Polish.
#
# fakeroot is not optional the way its man pages are: makepkg cannot build a
# package without it. Same arbitration as --auto-features auto in
# build-stage2.sh, and the same note for stage 3.
set -euo pipefail
python3 - <<'ZZPY'
import io, re
lines = io.open("PKGBUILD", encoding="utf-8").read().split("\n")
hit = [i for i, l in enumerate(lines) if re.match(r"^[ \t]*po4a\b", l)]
assert len(hit) == 1, "fakeroot: expected one po4a call, got %d" % len(hit)
lines[hit[0]] = "  # po4a call removed: no Perl module stack at either stage."
out = []
for l in lines:
    # makedepends too, or --nodeps is the only thing hiding the gap.
    out.append(l.replace(" 'po4a'", "") if "makedepends" in l else l)
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(out))
ZZPY
grep -qE "^[ \t]*po4a " PKGBUILD && { echo "fakeroot: a po4a call survived" >&2; exit 1; }
grep -q "po4a call removed" PKGBUILD || { echo "fakeroot: nothing was removed" >&2; exit 1; }
echo "fakeroot: translated man pages dropped"
