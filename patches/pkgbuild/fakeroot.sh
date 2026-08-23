#!/usr/bin/env bash
# fakeroot: no translated man pages, and no attempt to install them.
#
# First attempt removed the po4a call and nothing else. build() then ended on a
# bare `cd doc`, and package() failed with
#
#   install: cannot stat './faked.1': No such file or directory
#
# The English man pages are shipped -- doc/faked.1 and doc/fakeroot.1 are in the
# tree. What is NOT shipped is their translations: doc/Makefile carries
#
#   SUBDIRS = de es fr nl pt ro sv
#
# and each of those directories holds only Makefiles, with man_MANS naming
# fakeroot.1 and faked.1 that po4a was supposed to generate. So `make install`
# recursed into doc/fr and tried to install a file nobody had written. Removing
# the generator without removing the recursion left the second half of the job
# undone, which is the same mistake as removing a build target and leaving its
# install target -- eight packages in this port have now failed that way.
#
# WHY NOT po4a. It is Perl, and packaging it means packaging its module stack --
# perl-yaml-tiny, perl-syntax-keyword-try, perl-term-readkey and more -- so that
# fakeroot's man page exists in Polish. fakeroot itself is not optional: makepkg
# cannot build a package without it.
#
# The English man pages ARE still installed. Only the translations are dropped.
set -euo pipefail
python3 - <<'ZZPY'
import io, re
lines = io.open("PKGBUILD", encoding="utf-8").read().split("\n")
po = [i for i, l in enumerate(lines) if re.match(r"^[ \t]*po4a\b", l)]
assert len(po) == 1, "fakeroot: expected one po4a call, got %d" % len(po)
i = po[0]
# The `cd doc` immediately above exists only to run po4a.
assert re.match(r"^[ \t]*cd doc[ \t]*$", lines[i - 1]), \
    "fakeroot: expected `cd doc` above the po4a call, found %r" % lines[i - 1]
ind = re.match(r"^[ \t]*", lines[i - 1]).group(0)
lines[i - 1:i + 1] = [
    ind + "# po4a is not available at either stage, so the translated man pages",
    ind + "# are never generated -- and doc/<lang>/Makefile would still try to",
    ind + "# install them. Cut the recursion instead of leaving it to fail.",
    ind + 'sed -i "s/^SUBDIRS = de es fr nl pt ro sv$/SUBDIRS =/" doc/Makefile',
]
out = [l.replace(" 'po4a'", "") if "makedepends" in l else l for l in lines]
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(out))
ZZPY
grep -qE "^[[:space:]]*po4a " PKGBUILD && { echo "fakeroot: a po4a call survived" >&2; exit 1; }
grep -q 'SUBDIRS =/' PKGBUILD || { echo "fakeroot: the doc recursion was not cut" >&2; exit 1; }
grep -q "'po4a'" PKGBUILD && { echo "fakeroot: po4a still in makedepends" >&2; exit 1; }
echo "fakeroot: translated man pages dropped, recursion cut"
