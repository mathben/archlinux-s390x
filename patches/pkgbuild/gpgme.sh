#!/usr/bin/env bash
# gpgme: do not build the gpg test harness.
#
#   make[3]: Entering directory '.../gpgme/tests/gpg'
#   gpgconf: error running '/usr/bin/gpg-connect-agent': exit status 1
#   gpgconf: error running '/usr/bin/gpg-connect-agent KILLDIRMNGR': General error
#
# This is not check() -- EL_NOCHECK skips that. gpgme's `make all` descends into
# tests/gpg and SETS UP a throwaway GNUPGHOME, which means starting an agent.
# Inside the chroot there is no dbus, no session and no tty, so the agent cannot
# come up and the setup fails while merely building.
#
# --disable-gpg-test is gpgme's own switch, and the PKGBUILD already passes its
# sibling --disable-gpgsm-test for the same kind of reason. This is the third
# time this port has found that "no tests" and "no test harness" are different
# requests: skipping check() does not stop `make all` from building what check()
# would have run.
set -euo pipefail
python3 - <<'ZZPY'
import io, re
lines = io.open("PKGBUILD", encoding="utf-8").read().split("\n")
hit = [i for i, l in enumerate(lines) if re.match(r"^[ \t]*--disable-gpgsm-test", l)]
assert len(hit) == 1, "gpgme: expected one --disable-gpgsm-test, got %d" % len(hit)
i = hit[0]
ind = re.match(r"^[ \t]*", lines[i]).group(0)
cont = lines[i].rstrip().endswith("\\")
# Insert BEFORE, so the continuation state of the last option is untouched --
# adding a line after a final option that has no backslash would end the command.
lines.insert(i, ind + "--disable-gpg-test \\")
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lines))
ZZPY
grep -q -- "--disable-gpg-test" PKGBUILD || { echo "gpgme: the flag was not added" >&2; exit 1; }
grep -B1 -- "--disable-gpgsm-test" PKGBUILD | grep -q -- "--disable-gpg-test" || {
    echo "gpgme: the flag is not adjacent to its sibling" >&2; exit 1; }
echo "gpgme: gpg test harness not built"
