#!/usr/bin/env bash
# systemd: two build options Arch can hold and s390x cannot.
#
# Neither is a missing host package -- both are hard errors raised by meson
# because the PKGBUILD ASKS for something that does not exist on this
# architecture, so no amount of apt-get makes them go away. The libraries
# systemd wants (libbpf, clang, libfdisk, libkmod, ...) ARE host packages and
# belong in install_host_deps, not here.
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
