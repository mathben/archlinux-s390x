#!/usr/bin/env bash
# tpm2-tss: no unit tests, because their framework is not here.
#
#   configure: error: Unit test enabled, but cmocka missing or version
#
# This is the second obstacle in this package, and the first one hid it: before
# autoconf-archive existed, configure died on
#
#   configure.ac:139: error: undefined or overquoted macro: AC_MSG_WARN
#
# which named a macro that exists. An AX_* macro was missing, m4 quoting came
# apart, and autoconf blamed the next thing it recognised. With the archive
# installed, configure gets far enough to ask for cmocka.
#
# cmocka is a C unit-test framework, wanted only to build tests that this
# bootstrap does not run -- makepkg is invoked with --nocheck for the whole first
# pass. --disable-unit is tpm2-tss's own switch; the PKGBUILD passes --enable-unit
# in its options array.
set -euo pipefail
python3 - <<'ZZPY'
import io, re
lines = io.open("PKGBUILD", encoding="utf-8").read().split("\n")
hit = [i for i, l in enumerate(lines) if re.match(r"^[ \t]*--enable-unit[ \t]*$", l)]
assert len(hit) == 1, "tpm2-tss: expected one --enable-unit, got %d" % len(hit)
lines[hit[0]] = lines[hit[0]].replace("--enable-unit", "--disable-unit")
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lines))
ZZPY
grep -q -- "--disable-unit" PKGBUILD || { echo "tpm2-tss: unit tests not disabled" >&2; exit 1; }
grep -qE "^[[:space:]]*--enable-unit[[:space:]]*$" PKGBUILD && {
    echo "tpm2-tss: --enable-unit survived" >&2; exit 1; }
echo "tpm2-tss: unit tests disabled (no cmocka)"

# --- and no integration tests -------------------------------------------------
#
#   configure: error: Missing required program 'ss': ensure it is installed
#
# The THIRD obstacle in this package, each hidden by the one before it: a missing
# AX_* macro, then cmocka, now `ss`. configure.ac has
#
#   [ERROR_IF_NO_PROG([ss])]
#
# inside the integration-test branch. `ss` comes from iproute2, and adding
# iproute2 was the first idea -- it is in Arch's base group and belongs in this
# distribution eventually. It was MEASURED first: iproute2 depends on libbpf,
# iptables and linux-atm, none of which are here, and libbpf is the dependency
# systemd was already spared for the same reason.
#
# Three packages to satisfy a test-suite prerequisite, or one flag. The tests are
# not run: makepkg gets --nocheck for the whole first pass.
python3 - <<'ZZPY'
import io, re
lines = io.open("PKGBUILD", encoding="utf-8").read().split("\n")
en = [i for i, l in enumerate(lines) if re.match(r"^[ \t]*--enable-integration[ \t]*$", l)]
if en:
    lines[en[0]] = lines[en[0]].replace("--enable-integration", "--disable-integration")
else:
    # Put it beside the unit-test switch this hook already set.
    u = [i for i, l in enumerate(lines) if re.match(r"^[ \t]*--disable-unit[ \t]*$", l)]
    assert len(u) == 1, "tpm2-tss: expected the --disable-unit line from the section above"
    ind = re.match(r"^[ \t]*", lines[u[0]]).group(0)
    lines.insert(u[0] + 1, ind + "--disable-integration")
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lines))
ZZPY
grep -q -- "--disable-integration" PKGBUILD || {
    echo "tpm2-tss: integration tests not disabled" >&2; exit 1; }
echo "tpm2-tss: integration tests disabled (ss would cost three packages)"
