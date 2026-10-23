#!/usr/bin/env bash
# Boot the deployment image under QEMU.
#
# WHERE THE KERNEL COMES FROM. A z guest IPLs from a boot record that zipl
# writes, and s390-tools is not part of this port -- so the kernel is read OUT
# of the image and handed to -kernel. debugfs does that read: it walks ext4
# without root and without a mount, so a running guest is never the reason a
# copy is stale. root=/dev/vda needs no initramfs, because ext4, virtio-blk and
# the CCW transport are built in rather than modules; that is what the sixteen
# assertions in patches/pkgbuild/linux.sh are for.
#
# WHY THE NIC IS -ccw AND NOT -pci. A QEMU s390x guest has no PCI bus unless
# one is built for it. virtio-net-pci is accepted on the command line and then
# the guest sees no interface at all -- a failure that looks like a driver
# problem and is a bus problem.
#
# WHEN TO USE THIS AND NOT libvirt. scripts/install-libvirt-domain.sh defines a
# domain that autostarts, takes an address of its own and offers a console
# through virsh; that is the deployment. This script is for booting a variant
# without touching the defined domain -- another image, another kernel, another
# memory size -- and it refuses to run while that domain holds the same image.
#
# WHY user-mode networking. The guest needs to REACH github and pypi, and
# nothing needs to reach the guest except this host: -netdev user gives the
# first for free and the second through hostfwd, with no bridge, no tap, and no
# root. It costs ICMP -- ping does not work from inside -- and that is all.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="${WORK:-$HOME/work/arch-s390x}"
IMG="${IMG:-$WORK/arch-s390x.img}"
# ${VAR-default}, NOT ${VAR:-default}: KERNEL= means "IPL from the disk", and
# the colon form cannot tell an empty value from an unset one -- it would hand
# back the default and boot -kernel while the caller asked for the opposite.
KERNEL="${KERNEL-$WORK/vm-vmlinuz}"
VM_CPUS="${VM_CPUS:-4}"
VM_MEM="${VM_MEM:-6144}"
# Loopback only: this host is shared, and a guest with a password-less root
# console has no business listening on its public address.
SSH_PORT="${SSH_PORT:-2222}"
HTTP_PORT="${HTTP_PORT:-8069}"
CONSOLE="${CONSOLE:-$WORK/vm-console.txt}"
PIDFILE="${PIDFILE:-$WORK/vm.pid}"
# The libvirt domain that boots the same image, when one is defined.
DOMAIN="${DOMAIN:-arch-s390x}"

die() { echo "run-vm: $*" >&2; exit 1; }

[ -f "$IMG" ] || die "no image at $IMG"
command -v qemu-system-s390x >/dev/null || die "qemu-system-s390x is not installed"

# TWO WRITERS ON ONE EXT4 IMAGE DESTROY IT, and libvirt knows nothing about a
# qemu it did not start, so the check belongs here. What matters is the IMAGE,
# not the domain: booting a second, different image beside the running one is
# the normal way to try a build, and a guard that forbids it forbids the very
# thing this script is for.
if command -v virsh >/dev/null 2>&1 \
   && virsh --connect qemu:///system domstate "$DOMAIN" 2>/dev/null | grep -q running \
   && virsh --connect qemu:///system domblklist "$DOMAIN" 2>/dev/null | grep -qF " $IMG"; then
    die "the libvirt domain $DOMAIN is running on $IMG -- virsh shutdown $DOMAIN first"
fi

# The kernel, refreshed whenever the image carries a newer one. Arch's linux
# package puts the image at /usr/lib/modules/<version>/vmlinuz and lets an alpm
# hook copy it to /boot; both are tried, in the order that survives a hook that
# did not run.
extract_kernel() {
    local src
    for src in /boot/vmlinuz-linux $(debugfs -R "ls -p /usr/lib/modules" "$IMG" 2>/dev/null \
                | tr '/' '\n' | grep -E '^[0-9]+\.[0-9]' | sed 's|^|/usr/lib/modules/|;s|$|/vmlinuz|'); do
        if debugfs -R "dump $src $KERNEL.new" "$IMG" 2>/dev/null && [ -s "$KERNEL.new" ]; then
            mv "$KERNEL.new" "$KERNEL"
            echo "run-vm: kernel from $src ($(stat -c%s "$KERNEL") bytes)"
            return 0
        fi
        rm -f "$KERNEL.new"
    done
    return 1
}

# `stop` kills a running guest; reading a kernel out of the image for that is
# work done for nothing, and it touches a file the running qemu owns.
if [ "${1:-attached}" = stop ]; then
    [ -s "$PIDFILE" ] || die "no pidfile at $PIDFILE"
    pid="$(cat "$PIDFILE")"
    kill "$pid" && echo "run-vm: signalled $pid"
    exit 0
fi

# KERNEL= (empty) means IPL: the guest boots the record zipl wrote on its own
# disk, the way a z machine actually starts, and no kernel is read out of the
# image at all. That is the end state; -kernel remains for an image on which
# zipl has never run.
if [ -n "$KERNEL" ]; then
    if ! extract_kernel; then
        [ -f "$KERNEL" ] || die "no kernel in the image and none cached at $KERNEL"
        echo "run-vm: image carries no kernel, using the cached $KERNEL" >&2
    fi
else
    echo "run-vm: IPL from the disk's own boot record"
fi

QEMU_ARGS=(
    -machine s390-ccw-virtio,accel=kvm
    -smp "$VM_CPUS" -m "$VM_MEM"
    -nographic -no-reboot
    -drive "file=$IMG,format=raw,if=none,id=rootdisk,cache=writeback"
    # bootindex is what makes the disk an IPL candidate; without it QEMU has
    # nothing to start when no -kernel is given.
    -device virtio-blk-ccw,drive=rootdisk,bootindex=1
    -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:$SSH_PORT-:22,hostfwd=tcp:127.0.0.1:$HTTP_PORT-:8069"
    -device virtio-net-ccw,netdev=net0
)

if [ -n "$KERNEL" ]; then
    QEMU_ARGS+=(
        -kernel "$KERNEL"
        # PARTUUID, not /dev/vda: the image is partitioned, and the device
        # name is handed out by probe completion order rather than by bus
        # order. This path attaches one disk and would survive the name,
        # but it would mount a partition table as a filesystem.
        -append "root=PARTUUID=5390a7c4-01 rw console=ttysclp0 systemd.journald.forward_to_console=1"
    )
fi

case "${1:-attached}" in
    attached)
        echo "run-vm: console on this terminal, Ctrl-A X to leave"
        exec qemu-system-s390x "${QEMU_ARGS[@]}"
        ;;
    detach)
        # setsid, because the guest must outlive the ssh session that started
        # it -- and a link that drops is not a guest that stopped.
        : > "$CONSOLE"
        setsid nohup qemu-system-s390x "${QEMU_ARGS[@]}" \
            -pidfile "$PIDFILE" > "$CONSOLE" 2>&1 < /dev/null &
        sleep 2
        [ -s "$PIDFILE" ] || die "qemu did not start, see $CONSOLE"
        echo "run-vm: pid $(cat "$PIDFILE"), console in $CONSOLE"
        echo "run-vm: ssh -p $SSH_PORT root@127.0.0.1, http on 127.0.0.1:$HTTP_PORT"
        ;;
    *)
        die "usage: $(basename "$0") [attached|detach|stop]"
        ;;
esac
