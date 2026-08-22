#!/usr/bin/env bash
# systemd: four defaults Arch can hold and s390x cannot.
#
# None of them is a missing host package. Two are hard errors raised by meson
# because the PKGBUILD ASKS for something this architecture does not have; two
# are defaults computed from the BUILD MACHINE rather than the target. No
# amount of apt-get fixes any of them. The libraries systemd wants (libbpf,
# clang, libfdisk, libkmod, ...) ARE host packages and belong in
# install_host_deps, not here.
#
# Three of the four fail with a message that names something else entirely.
# Each section says which, because that is the part worth reading twice.
set -euo pipefail

# 1. -Dbootloader=enabled: systemd-boot is EFI, and s390x has no EFI.
#
# The message you get is NOT about EFI:
#
#   systemd/meson.build:1638:19: ERROR: python3 is missing modules: elftools
#
# because meson.build:1638 asks for pyelftools with
# `required : get_option('bootloader')`, and the PKGBUILD set that to enabled.
#
# THE TRAP is that this reads like a missing host package, and
# `apt install python3-pyelftools` looks like the fix. It is not. It buys four
# lines, and then meson.build:1642 says what is really wrong:
#
#   ERROR: Feature bootloader cannot be enabled: unsupported EFI arch or
#          EFI support is disabled
#
# (verified by planting a stub elftools module on PYTHONPATH; without it the
#  EFI message is unreachable, which is why nobody ever sees it first.)
#
# meson.build:1627 maps a cpu family to an EFI machine type name -- aa64, arm,
# loongarch32/64, riscv32/64, x64, ia32 -- and s390x is not in that table, so
# efi_arch is ''. -Defi is still true; the architecture simply has no EFI.
# IBM Z boots from an IPL record, there is no ESP for systemd-boot to write
# into, and no configuration invents one.
#
# The cost is the systemd-boot artefacts. bootctl itself is still built and
# installed -- checked in the install plan -- package_systemd() names neither,
# and the arch.conf/loader.conf/splash-arch.bmp it ships are `install`ed from
# $srcdir rather than built. Packaging is untouched. Disabling also drops the
# pyelftools requirement in the same line.
sed -i 's/-Dbootloader=enabled/-Dbootloader=disabled/' PKGBUILD
grep -q -- '-Dbootloader=disabled' PKGBUILD || {
    echo "systemd: bootloader option not rewritten" >&2; exit 1; }
echo "systemd: bootloader disabled (s390x has no EFI machine type)"

# 2. -Dvmlinux-h=provided: the file Arch points at is an Arch file.
#
#   src/bpf/meson.build:  error('Path to provided vmlinux.h does not exist.')
#
# Arch's linux-headers ships /usr/src/linux/vmlinux.h, the path hard-coded in
# the PKGBUILD. Ubuntu's linux-headers-* ship no vmlinux.h anywhere. This
# failure only appears AFTER libbpf and clang are installed, because the whole
# block is skipped while BPF_FRAMEWORK is off -- fixing libbpf uncovers it.
#
# systemd's own fallback dumps the header out of the running kernel's BTF,
# which is what 'generated' selects:
#
#   bpftool btf dump file /sys/kernel/btf/vmlinux format c
#
# Checked on this host: exit 0, 122471 lines, and enum lsm_integrity_type is
# there at line 15931, so restrict-fsaccess.bpf.c builds rather than being
# quietly dropped.
#
# THE TRAP is that 'auto' would NOT have done this for us. The auto branch
# generates only when `host_machine.cpu_family() in ['x86_64', 'aarch64']`; on
# s390x it falls through to "neither provided nor generated" and silently
# drops the BPF programs that need the header. s390x has to say it out loud.
#
# Note the asymmetry this buys: on the 'provided' branch systemd probes the
# header with cc.compiles() before deciding what to build. On 'generated' it
# sets have_lsm_integrity_type = true outright. So the build now depends on
# the BTF of the kernel RUNNING when it starts -- fine on 6.17.0-41, and on an
# older kernel it turns into a compile error with no fallback.
#
# -Dvmlinux-h-path goes with it: 'generated' ignores the value, and leaving a
# path that resolves to nothing invites the next reader to "repair" it.
sed -i 's/-Dvmlinux-h=provided/-Dvmlinux-h=generated/' PKGBUILD
sed -i '/-Dvmlinux-h-path=/d' PKGBUILD
grep -q -- '-Dvmlinux-h=generated' PKGBUILD || {
    echo "systemd: vmlinux.h still read from a provided path" >&2; exit 1; }
grep -q -- '-Dvmlinux-h-path' PKGBUILD && {
    echo "systemd: stale vmlinux-h-path left in place" >&2; exit 1; }
echo "systemd: vmlinux.h generated from /sys/kernel/btf/vmlinux"

# 3. -Dsplit-bin=auto: the question is answered by the HOST, not the target.
#
#   systemd/meson.build:123
#     sbindir = prefixdir / (split_bin ? 'sbin' : 'bin')
#
# split-bin is a combo defaulting to 'auto', and 'auto' probes whether
# /usr/sbin on the BUILD MACHINE is a symlink to bin. On Arch it is, so
# split_bin is false and everything lands in /usr/bin. Here /usr/sbin is a
# real directory, and meson-log.txt says so:
#
#   split bin-sbin                           : true
#
# THE TRAP is that arch-meson ALREADY passes --sbindir bin, and
# `meson configure` dutifully reports sbindir = bin. It is ignored: systemd
# computes its own sbindir from split_bin and never reads meson's builtin. The
# option that looks like the fix is not the fix, and the one that is mentions
# neither sbin nor a directory in its name.
#
# Nothing fails in build(). It fails much later, in package_systemd(), on the
# first line that names a path:
#
#   rm: cannot remove '<pkgdir>/usr/bin/halt': No such file or directory
#
# because halt, init, poweroff, reboot, shutdown and resolvconf all went to
# /usr/sbin -- along with mount.ddi, mount.mstack and mount.storage, which the
# PKGBUILD never mentions at all. The rm is only the first victim. Suppress it
# and the package ships /usr/sbin as a DIRECTORY, which collides on the target
# with the ["usr/sbin"]="bin" SYMLINK our own filesystem package declares.
#
# Measured on a configured copy: with split-bin=false there is no /usr/sbin in
# the install tree at all, and all six paths are where package() looks.
#
# Same species as arch-meson's --libdir -- an Ubuntu default standing in for
# an Arch one -- but it cannot live in arch-meson: split-bin is systemd's own
# option, not a meson builtin. --auto-features does not reach it either; it is
# a combo, not a feature.
test "$(grep -c -- '-Dcompat-sysv-interfaces=false' PKGBUILD)" -eq 1 || {
    echo "systemd: expected exactly one _meson_options array" >&2; exit 1; }
test "$(grep -c -- '-Dsplit-bin' PKGBUILD)" -eq 0 || {
    echo "systemd: PKGBUILD already sets split-bin, re-read it" >&2; exit 1; }
sed -i 's/^\( *\)-Dcompat-sysv-interfaces=false/\1-Dsplit-bin=false\n\1-Dcompat-sysv-interfaces=false/' PKGBUILD
grep -q -- '-Dsplit-bin=false' PKGBUILD || {
    echo "systemd: split-bin still auto (would install into /usr/sbin)" >&2; exit 1; }
echo "systemd: split-bin=false (Ubuntu's /usr/sbin is not Arch's)"

# 4. -Dukify=auto: the tool cannot run on this architecture at all.
#
# ukify assembles a Unified Kernel Image, and a UKI is a PE binary -- ukify.py
# imports pefile at module level and drives it directly (pefile.PE,
# SectionStructure, IMAGE_SCN_*). It is EFI tooling, so the same reasoning as
# section 1 applies. But it is stronger than "pointless on Z", and the source
# says so out loud:
#
#   EFI_ARCH_MAP = {
#       'x86_64': ['x64','ia32'], 'i[3456]86': ['ia32'], 'aarch64': ['aa64'],
#       'armv[45678]*l': ['arm'], 'loongarch32': ..., 'riscv64': ...
#   }
#
#   def guess_efi_arch() -> str:
#       ...
#       else:
#           raise ValueError(f'Unsupported architecture {arch}')
#
# s390x is not in that table, so ukify RAISES on this machine. Shipping it
# would put a program in the repository that cannot start.
#
# THE TRAP is that ukify does not announce itself as EFI-only anywhere the
# build stops. meson_options.txt:560 declares it a plain feature with no
# value -- 'auto' -- and meson.build:1659 is get_option('ukify').allowed(),
# which is true for 'auto'. So it is on by default, and what it broke was
# nowhere near ukify:
#
#   FAILED: src/boot/test-hwids-section.c
#   ModuleNotFoundError: No module named 'pefile'
#
# That looked like a missing host package, and `apt install python3-pefile`
# made it build. It was the wrong fix: the target at src/boot/meson.build:31
# is gated on ENABLE_UKIFY, not on ENABLE_BOOTLOADER, which is why disabling
# systemd-boot did not reach it. Disabling ukify does, and python3-pefile is
# then unnecessary -- nothing else in the tree needs it, since the only other
# importer, tools/check-efi-alignment.py, is reached from
# src/boot/meson.build:495, far below the ENABLE_BOOTLOADER subdir_done()
# guard.
#
# systemd-tests goes with it, for a different reason. It is a test suite --
# stage 1 runs --nocheck -- and it is the sole reason five python packages
# (colorama, packaging, pexpect, psutil, pytest) would enter the closure.
# Deferred, not architectural: TODO.md records it.
#
# The two subpackages leave in three places, and the pkgname array is the
# awkward one: its LAST entry carries the closing paren, so deleting a line
# would delete the ')' with it. The array is rebuilt rather than edited.
python3 - <<'PY'
import io, re
s = io.open("PKGBUILD", encoding="utf-8").read()

# (a) the option, next to the other EFI one so they read together
anchor = "    -Dbootloader=disabled\n"
assert s.count(anchor) == 1, "expected section 1 to have set bootloader=disabled"
s = s.replace(anchor, anchor + "    -Dukify=disabled\n", 1)

# (b) the pkgname array, rebuilt to keep its syntax intact
m = re.search(r"pkgname=\((.*?)\)\n", s, re.S)
assert m, "pkgname array not found"
names = re.findall(r"'([^']+)'", m.group(1))
drop = {"systemd-ukify", "systemd-tests"}
assert drop <= set(names), "expected both subpackages in pkgname, found %s" % names
kept = [n for n in names if n not in drop]
s = s[:m.start()] + "pkgname=(" + ("\n" + " " * 9).join("'%s'" % n for n in kept) + ")\n" + s[m.end():]

# (c) package_systemd() moves four ukify paths out. With ukify disabled none
#     of them exists, and mv fails -- after a successful compile, which is the
#     expensive way to find out.
blk = re.search(
    r"\n  # ukify shipped in separate package\n"
    r"(?:.*\n)*?"
    r"  mv \"\$pkgdir\"/usr/lib/kernel/install\.d/60-ukify\.install systemd-ukify/install\.d\n",
    s)
assert blk, "ukify mv block not found"
s = s[:blk.start()] + "\n" + s[blk.end():]

# (d) an optdepends on a package we no longer produce
s = re.sub(r"^.*'systemd-ukify: .*\n", "", s, flags=re.M)

io.open("PKGBUILD", "w", encoding="utf-8").write(s)
PY
# The guard checks what MATTERS, which is not "no mention of ukify remains".
# package_systemd-ukify() still sits in the file and still names four paths --
# harmless, because makepkg never calls a function whose name is absent from
# pkgname, exactly as with package_libquadmath() in gcc.sh. Counting mentions
# instead of checking the two real conditions made this hook exit 1 on a
# correctly patched PKGBUILD, and build_package reads that as a failed
# package: systemd would have been skipped entirely, with every edit applied.
grep -q -- '-Dukify=disabled' PKGBUILD || {
    echo "systemd: ukify still enabled" >&2; exit 1; }
grep -q '# ukify shipped in separate package' PKGBUILD && {
    echo "systemd: package_systemd() still moves ukify paths that cannot exist" >&2
    exit 1; }
python3 - <<'PYGUARD'
import io, re, sys
s = io.open("PKGBUILD", encoding="utf-8").read()
m = re.search(r"pkgname=\((.*?)\)\n", s, re.S)
if not m:
    sys.exit("systemd: pkgname array unreadable after patching")
names = re.findall(r"'([^']+)'", m.group(1))
left = sorted({"systemd-ukify", "systemd-tests"} & set(names))
if left:
    sys.exit("systemd: still declared in pkgname: %s" % left)
print("systemd: pkgname -> %s" % " ".join(names))
PYGUARD
echo "systemd: ukify disabled (guess_efi_arch raises on s390x), tests dropped"

# --- no BPF framework ---------------------------------------------------------
#
#   meson.build:1052:9: ERROR: Dependency "libbpf" not found (tried pkgconfig)
#
# libbpf is not in this port's package list, and adding it is not a small step:
# systemd's BPF programs are compiled with clang and llvm, so the dependency is
# an entire second compiler toolchain for a feature that only matters to
# systemd's own resource-control and socket-binding units.
#
# -Dbpf-framework=disabled is systemd's own switch for building without it,
# which is what every distribution that does not ship BPF-based unit features
# uses. Revisit if something on the target actually needs IPAddressAllow= or
# RestrictNetworkInterfaces=.
set -euo pipefail
python3 - <<'ZZPY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()
old = "-Dbpf-framework=enabled"
assert s.count(old) == 1, "systemd: expected one bpf-framework option, got %d" % s.count(old)
s = s.replace(old, "-Dbpf-framework=disabled", 1)
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
ZZPY
grep -q -- "-Dbpf-framework=disabled" PKGBUILD || {
    echo "systemd: bpf-framework was not disabled" >&2; exit 1; }
echo "systemd: BPF framework disabled (no libbpf, no clang)"
