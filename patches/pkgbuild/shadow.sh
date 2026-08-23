#!/usr/bin/env bash
set -euo pipefail

# --- no man pages -------------------------------------------------------------
#
#   install: cannot stat './man5/gshadow.5': No such file or directory
#   install: cannot stat './man8/groupdel.8': No such file or directory
#
# shadow renders its man pages from DocBook with xsltproc. xsltproc EXISTS here
# now -- our libxslt supplies it -- and that is what makes this one worth
# distinguishing: what is missing is the DocBook XML data the stylesheets need,
# not the tool. Exactly pam's situation.
#
# TWO PLACES: --enable-man in the configure options and an explicit
# `make -C man install` in package(). The second is the one that reported the
# failure, and removing only it would leave configure still trying to build them.
set -euo pipefail
python3 - <<'ZZPY'
import io, re
lines = io.open("PKGBUILD", encoding="utf-8").read().split("\n")
en = [i for i, l in enumerate(lines) if re.match(r"^[ \t]*--enable-man[ \t]*$", l)]
assert len(en) == 1, "shadow: expected one --enable-man, got %d" % len(en)
lines[en[0]] = lines[en[0]].replace("--enable-man", "--disable-man")
inst = [i for i, l in enumerate(lines) if re.search(r"make .*-C man install", l)]
assert len(inst) == 1, "shadow: expected one `make -C man install`, got %d" % len(inst)
ind = re.match(r"^[ \t]*", lines[inst[0]]).group(0)
lines[inst[0]] = ind + ": # man pages need DocBook XML data, which this port lacks."
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lines))
ZZPY
grep -q -- "--disable-man" PKGBUILD || { echo "shadow: man not disabled" >&2; exit 1; }
grep -qE "make .*-C man install" PKGBUILD && {
    echo "shadow: the man install survived" >&2; exit 1; }
echo "shadow: man pages disabled (DocBook data absent, not xsltproc)"
