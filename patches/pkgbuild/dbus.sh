#!/usr/bin/env bash
# dbus: three documentation generators, made mandatory by arch-meson.
#
# The build stopped three times in a row, on a different tool each time:
#
#   ERROR: Program 'ducktype' not found or not executable
#   ERROR: Program 'yelp-build' not found or not executable
#   ERROR: Program 'qhelpgenerator qhelpgenerator-qt5' not found
#
# Each looked like its own missing host package, and the first two were duly
# installed. THE TRAP is that chasing them one at a time is the wrong shape:
# the third needs Qt, so the chain does not terminate anywhere reasonable, and
# none of the three was ever really required.
#
# meson.build asks for them like this:
#
#   doxygen   = find_program('doxygen',      required: get_option('doxygen_docs'))
#   ducktype  = find_program('ducktype',     required: get_option('ducktype_docs'))
#   yelpbuild = find_program('yelp-build',   required: get_option('ducktype_docs'))
#   qhelpgen  = find_program('qhelpgenerator', ..., required: get_option('qt_help'))
#
# and all three options are features declared with no value -- 'auto'.
# arch-meson passes --auto-features enabled, which promotes every one of them
# to a hard requirement. On Arch that is harmless: the doc tools are in the
# build chroot. Here it turned optional documentation into three consecutive
# build failures. Same mechanism as util-linux's translated man pages and
# expat's docbook converter; dbus is just the clearest instance, because it
# repeated three times in one afternoon.
#
# xml_docs is deliberately LEFT ALONE: it generates the man pages through
# xsltproc, which is installed, and man pages are worth having.
#
# The dbus-docs sub-package goes with the options. Its `_pick docs
# usr/share/doc` is a mv, so with nothing generated it would fail the way
# every other _pick on an absent path in this port has failed -- after a
# successful compile, at the last step, naming a directory rather than a
# reason. Deferred, not architectural: TODO.md records the way back.
set -euo pipefail
python3 - <<'PY'
import io, re
s = io.open("PKGBUILD", encoding="utf-8").read()

# (a) pin the three features off, beside the options already being pinned
anchor = "    -D apparmor=disabled\n"
assert s.count(anchor) == 1, "dbus: meson_options array not in the expected form"
s = s.replace(anchor,
              anchor +
              "    -D doxygen_docs=disabled\n"
              "    -D ducktype_docs=disabled\n"
              "    -D qt_help=disabled\n", 1)

# (b) the sub-package that would have nothing to package
m = re.search(r"pkgname=\((.*?)\)\n", s, re.S)
assert m, "dbus: pkgname array not found"
names = [n for n in re.findall(r"[A-Za-z0-9._+-]+", m.group(1))]
assert "dbus-docs" in names, "dbus: dbus-docs not in pkgname"
kept = [n for n in names if n != "dbus-docs"]
s = s[:m.start()] + "pkgname=(\n" + "".join("  %s\n" % n for n in kept) + ")\n" + s[m.end():]

# (c) and the _pick that feeds it
old = '  _pick docs "$pkgdir"/usr/share/doc\n'
assert s.count(old) == 1, "dbus: docs _pick not in the expected form"
s = s.replace(old, "", 1)

io.open("PKGBUILD", "w", encoding="utf-8").write(s)
PY
for o in doxygen_docs ducktype_docs qt_help; do
    grep -qF -- "-D $o=disabled" PKGBUILD || {
        echo "dbus: $o not pinned off" >&2; exit 1; }
done
grep -qF '_pick docs' PKGBUILD && {
    echo "dbus: docs _pick survived and would fail on an absent path" >&2; exit 1; }
python3 - <<'PY'
import io, re, sys
s = io.open("PKGBUILD", encoding="utf-8").read()
m = re.search(r"pkgname=\((.*?)\)\n", s, re.S)
if not m:
    sys.exit("dbus: pkgname array unreadable after patching")
names = re.findall(r"[A-Za-z0-9._+-]+", m.group(1))
if "dbus-docs" in names:
    sys.exit("dbus: dbus-docs still declared in pkgname")
print("dbus: pkgname -> %s" % " ".join(names))
PY
echo "dbus: doc generators pinned off (--auto-features made three of them fatal)"
