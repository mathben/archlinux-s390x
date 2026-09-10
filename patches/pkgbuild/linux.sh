#!/usr/bin/env bash
# linux: an s390x config, no htmldocs, no BTF header.
#
# THE CONFIG. prepare() already does `cp ../config.$CARCH .config` -- the same
# per-architecture hook that rust bootstrap toml turned out to be. Arch ships
# config.x86_64 and nothing else, so this generates the s390x config IN TREE
# rather than committing a five-thousand-line file nobody here could review:
#
#   make defconfig      # arch/s390/configs/defconfig, what distributions use
#   scripts/config ...  # the handful systemd and this deployment need
#   make olddefconfig
#
# WHY NOT THE KERNEL ALREADY IN boot/. It was cross-built in an earlier phase,
# it boots, it mounts an ext4 root over virtio-blk-ccw -- and it has no TCP/IP:
#
#   NET: Registered PF_NETLINK/PF_ROUTE, PF_UNIX, PF_XDP     (no PF_INET)
#   systemd-sysctl: Couldn't write to net/ipv4/tcp_keepalive_time
#   sshd: fatal: Cannot bind any address.
#
# A whole boot to find that out. So the enables below are asserted against the
# FINAL .config, after olddefconfig has had its say -- an option that silently
# did not take is exactly the shape that cost that boot.
#
# THE CCW TRANSPORT IS NAMED S390_GUEST, NOT VIRTIO_CCW. There is no
# CONFIG_VIRTIO_CCW: drivers/s390/virtio/Makefile builds virtio_ccw.o under
# CONFIG_S390_GUEST, which is the only symbol Kconfig offers for it. Asking for
# the driver by a name Kconfig does not know is the guard catching itself --
# the enable is a no-op and the assertion is what says so.
#
# htmldocs GOES. build() runs `make htmldocs SPHINXOPTS=-QT` unconditionally and
# python-sphinx is the tree this port has refused since llvm. linux-docs leaves
# pkgname with it: twenty-first appearance of that shape.
#
# BINFMT_MISC IS NOT IN THE s390 defconfig, AND systemd WANTS IT.
# proc-sys-fs-binfmt_misc.mount fails without it, which is enough to leave
# `systemctl is-system-running` reporting degraded on an otherwise clean boot.
# Nothing here executes a foreign binary format; the symbol is enabled so that
# a failed unit means something the day one appears.
#
# THE initramfs DEPENDENCY GOES. It is a virtual package, provided by
# mkinitcpio or dracut, and this port builds neither. Nor does it need one: the
# guest mounts an ext4 root over virtio-blk on the CCW bus, and all three are
# built into the image rather than loaded as modules -- which is what the
# assertions above exist to guarantee. Left in place, the dependency is
# unsatisfiable at install time and pacman refuses the whole transaction.
#
# THE HEADERS PACKAGE NAMES A DIRECTORY, NOT AN ARCHITECTURE.
# package_linux-headers() maps CARCH to the arch/ subdirectory it copies, and
# the map has one entry: x86_64 to x86. It is the SAME per-architecture hook
# again -- config.$CARCH, the rust bootstrap toml, and now this -- and it fails
# loudly, `Unknown CARCH s390x`, after the kernel itself has already built.
#
# AND THE BTF HEADER, which is the same shape a third time. Removing
# `make -C tools/bpf/bpftool vmlinux.h` is not enough -- package_linux-headers
# INSTALLS tools/bpf/bpftool/vmlinux.h, so the file leaves that list too.
set -euo pipefail
python3 - <<'ZZPY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()

# 1. la config s390x, engendree dans l arbre
old = """  cp ../config.$CARCH .config
  make olddefconfig"""
assert s.count(old) == 1, "linux: bloc de config introuvable"
new = """  if [ "$CARCH" = s390x ]; then
    # Arch ships no config.s390x. arch/s390/configs/defconfig is the base every
    # distribution starts from; these enables are what systemd and a QEMU guest
    # need on top, and they are verified below rather than hoped for.
    make defconfig
    scripts/config --enable INET --enable IPV6 \\
      --enable EXT4_FS --enable TMPFS --enable TMPFS_POSIX_ACL \\
      --enable DEVTMPFS --enable DEVTMPFS_MOUNT \\
      --enable VIRTIO --enable S390_GUEST --enable VIRTIO_BLK \\
      --enable VIRTIO_NET --enable VIRTIO_CONSOLE --enable VIRTIO_BALLOON \\
      --enable CGROUPS --enable NAMESPACES --enable NET_NS --enable PID_NS \\
      --enable USER_NS --enable UTS_NS --enable IPC_NS \\
      --enable SECCOMP --enable FANOTIFY --enable INOTIFY_USER \\
      --enable BINFMT_MISC \\
      --enable EPOLL --enable SIGNALFD --enable TIMERFD \\
      --enable BLK_DEV_LOOP --enable AUTOFS_FS
    make olddefconfig
    # Verifie, pas espere : une option qui n a pas pris coute un amorcage.
    for sym in INET IPV6 EXT4_FS TMPFS DEVTMPFS DEVTMPFS_MOUNT VIRTIO \\
               S390_GUEST VIRTIO_BLK VIRTIO_NET CGROUPS NAMESPACES NET_NS \\
               USER_NS SECCOMP FANOTIFY BINFMT_MISC; do
      grep -qx "CONFIG_$sym=y" .config || { echo "linux: CONFIG_$sym did not take" >&2; exit 1; }
    done
    echo "linux: s390x config generated, 17 required symbols verified"
  else
    cp ../config.$CARCH .config
    make olddefconfig
  fi"""
s = s.replace(old, new, 1)

# 5. package_linux-headers() ne sait traduire que x86_64
old = """    x86_64) karch=x86 ;;"""
assert s.count(old) == 1, "linux: case karch introuvable"
s = s.replace(old, """    x86_64) karch=x86 ;;
    s390x) karch=s390 ;;""", 1)

# 6. la dependance initramfs, qu aucun paquet d ici ne fournit
old = """  depends=(
    coreutils
    initramfs
    kmod
  )"""
assert s.count(old) == 1, "linux: depends de _package() introuvable"
s = s.replace(old, """  depends=(
    coreutils
    kmod
  )""", 1)

# 2. htmldocs et son attente
old = """  make htmldocs SPHINXOPTS=-QT &
  local pid_docs=$!

  make all
  make -C tools/bpf/bpftool vmlinux.h feature-clang-bpf-co-re=1
  wait $pid_docs"""
assert s.count(old) == 1, "linux: bloc build() introuvable"
s = s.replace(old, "  make all", 1)

# 3. linux-docs quitte pkgname
old = '  "$pkgbase-docs"\n'
assert s.count(old) == 1, "linux: entree docs de pkgname introuvable"
s = s.replace(old, "", 1)

# 4. le consommateur du vmlinux.h qui n existe plus
old = "    localversion.* version vmlinux tools/bpf/bpftool/vmlinux.h"
assert s.count(old) == 1, "linux: liste de linux-headers introuvable"
s = s.replace(old, "    localversion.* version vmlinux", 1)

io.open("PKGBUILD", "w", encoding="utf-8").write(s)
ZZPY
grep -q "s390x config generated" PKGBUILD || { echo "linux: la config s390x n a pas ete posee" >&2; exit 1; }
# `make htmldocs`, pas le mot: makedepends porte un "# htmldocs" COMMENTE, qui
# est du code juste. Un garde qui condamne ce que l edition n a pas touche est
# un garde qui ment -- ce port en a corrige cinq avant celui-ci.
grep -qE "^[[:space:]]*make htmldocs" PKGBUILD && { echo "linux: make htmldocs survit" >&2; exit 1; }
grep -q "bpftool/vmlinux.h" PKGBUILD && { echo "linux: un consommateur du vmlinux.h survit" >&2; exit 1; }
grep -q "pkgbase-docs" PKGBUILD && { echo "linux: linux-docs est encore un paquet" >&2; exit 1; }
grep -q "^  make all$" PKGBUILD || { echo "linux: make all a disparu" >&2; exit 1; }
grep -q "s390x) karch=s390" PKGBUILD || { echo "linux: karch s390 absent" >&2; exit 1; }
grep -qE "^    initramfs$" PKGBUILD && { echo "linux: la dependance initramfs survit" >&2; exit 1; }
echo "linux: config s390x, htmldocs et BTF retires"
