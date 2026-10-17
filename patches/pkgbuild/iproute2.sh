#!/usr/bin/env bash
# iproute2: declare what this build links, not what Arch's build links.
#
# The recipe declares libxtables.so, libbpf and libbpf.so. ./configure probes
# for them, and this port provides neither, so they are simply not compiled
# in. The declaration survives the probe, and pacman then refuses the package
# on a guest that has exactly what the package was built against:
#
#   :: unable to satisfy dependency 'libxtables.so' required by iproute2
#
# WHAT THE BINARIES ACTUALLY NEED, read from the package rather than assumed:
#
#   ip   NEEDED libelf.so.1, libcap.so.2, libc.so.6
#   tc   NEEDED libelf.so.1, libcap.so.2, libm.so.6, libc.so.6
#
# Both names still appear as STRINGS in ip and tc: tc opens xtables matches
# and BPF objects at runtime, by name, when a command asks for them. That is
# a runtime failure for those commands and not a link-time one, which is why
# the dependency is wrong rather than merely unsatisfied.
#
# WHAT IS LOST: `tc` actions that load an iptables match or a BPF program.
# Addressing, routing, links, neighbours, sockets -- everything `ip` and `ss`
# do -- are untouched.
#
# TO UNDO: build iptables and libbpf, drop this hook. Nothing else changes.
set -euo pipefail
python3 - <<'ZZPY'
import io, re
s = io.open("PKGBUILD", encoding="utf-8").read()

before = s
for dep in ("'libxtables.so'", "'libbpf'", "'libbpf.so'"):
    s = re.sub(r"[ \t]*" + re.escape(dep) + r"[ \t]*(#[^\n]*)?\n?", "", s, count=1)
assert s != before, "iproute2: aucune dependance retiree"

for dep in ("libxtables.so", "libbpf"):
    m = re.search(r"^depends=\(.*?\)", s, re.S | re.M)
    assert m, "iproute2: bloc depends introuvable"
    assert dep not in m.group(0), \
        "iproute2: %s survit dans depends" % dep

io.open("PKGBUILD", "w", encoding="utf-8").write(s)
ZZPY
bash -n PKGBUILD || { echo "iproute2: le PKGBUILD ne s analyse plus" >&2; exit 1; }
echo "iproute2: xtables et bpf retires des dependances declarees"
