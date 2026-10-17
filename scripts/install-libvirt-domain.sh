#!/usr/bin/env bash
# Define the deployment guest as a libvirt domain, so it survives a reboot of
# the host and is driven with virsh rather than a detached qemu process.
#
# WHAT THIS BUYS OVER scripts/run-vm.sh. Autostart, a console that attaches and
# detaches without killing anything (`virsh console`), and an address of its
# own on the NAT network instead of two forwarded ports. run-vm.sh stays: it is
# the way to boot a throwaway variant without touching the defined domain.
#
# THE ONE PERMISSION THIS NEEDS. qemu runs as libvirt-qemu, and a home
# directory is 0750, so libvirt-qemu cannot even traverse it. An ACL granting
# execute -- traverse, not read -- on that one directory is the smallest fix;
# moving a 24 GB image into /var/lib/libvirt would be the larger one, and that
# tree belongs to other work.
#
# EVERYTHING PATH-SHAPED IS SUBSTITUTED HERE, not committed. The templates in
# libvirt/ carry @TOKENS@ because a path with an account name in it does not
# belong in a repository.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TPL="$HERE/../libvirt"
WORK="${WORK:-$HOME/work/arch-s390x}"
NAME="${NAME:-arch-s390x}"
IMG="${IMG:-$WORK/arch-s390x.img}"
KERNEL="${KERNEL:-$WORK/vm-vmlinuz}"
NETWORK="${NETWORK:-default}"
# Empty means IPL -- the disk boots itself, which is what build-image.sh
# produces. Set it to a path only for an image zipl has never touched.
EL_EXTERNAL_KERNEL="${EL_EXTERNAL_KERNEL-}"
VCPU="${VCPU:-4}"
MEM="${MEM:-6144}"
HOOK=/etc/libvirt/hooks/qemu
CONNECT="${CONNECT:-qemu:///system}"

die() { echo "install-libvirt-domain: $*" >&2; exit 1; }
say() { printf '  %s\n' "$*"; }

[ -f "$IMG" ] || die "no image at $IMG"
[ -f "$TPL/arch-s390x.xml.in" ] || die "no template at $TPL"
command -v virsh >/dev/null || die "virsh is not installed"
EMULATOR="$(command -v qemu-system-s390x)" || die "qemu-system-s390x is not installed"

substitute() {
    sed -e "s|@NAME@|$NAME|g" -e "s|@IMG@|$IMG|g" -e "s|@KERNEL@|$KERNEL|g" \
        -e "s|@NETWORK@|$NETWORK|g" -e "s|@VCPU@|$VCPU|g" -e "s|@MEM@|$MEM|g" \
        -e "s|@EMULATOR@|$EMULATOR|g" \
        -e "/@KERNELTAGS@/{r $KERNELTAGS_FILE
d}" "$1"
}

# The two lines that hand a kernel in from outside, or nothing at all.
KERNELTAGS_FILE="$(mktemp)"
tmp=""
trap 'rm -f "$KERNELTAGS_FILE" "$tmp"' EXIT
if [ -n "$EL_EXTERNAL_KERNEL" ]; then
    KERNEL="$EL_EXTERNAL_KERNEL"
    printf '    <kernel>%s</kernel>\n    <cmdline>root=/dev/vda rw console=ttysclp0</cmdline>\n' \
        "$KERNEL" > "$KERNELTAGS_FILE"
fi

echo "== The network the domain attaches to =="
virsh --connect "$CONNECT" net-info "$NETWORK" >/dev/null 2>&1 \
    || die "libvirt network '$NETWORK' does not exist"
say "$NETWORK, $(virsh --connect "$CONNECT" net-info "$NETWORK" | awk '/Active/{print $2}')"

echo "== Traverse permission for libvirt-qemu =="
# Only the home directory needs it; everything below is already world-traversable.
if id libvirt-qemu >/dev/null 2>&1; then
    sudo setfacl -m u:libvirt-qemu:x "$HOME"
    say "$HOME: u:libvirt-qemu:x"
else
    say "no libvirt-qemu user on this host, skipping"
fi

if [ -z "$EL_EXTERNAL_KERNEL" ]; then
    echo "== Boot =="
    say "IPL: the disk carries its own boot record (zipl)"
else

echo "== The kernel, read out of the image =="
# Once here so that `virsh start` has something to boot even before the hook
# runs; the hook is what keeps it current afterwards.
found=
for src in $(debugfs -R "ls -p /usr/lib/modules" "$IMG" 2>/dev/null \
             | tr '/' '\n' | grep -E '^[0-9]+\.[0-9]' \
             | sed 's|^|/usr/lib/modules/|;s|$|/vmlinuz|') /boot/vmlinuz-linux; do
    if debugfs -R "dump $src $KERNEL.new" "$IMG" 2>/dev/null && [ -s "$KERNEL.new" ]; then
        mv "$KERNEL.new" "$KERNEL"; found="$src"; break
    fi
    rm -f "$KERNEL.new"
done
[ -n "$found" ] || [ -f "$KERNEL" ] || die "no kernel in the image and none cached"
say "${found:-cached $KERNEL} -> $KERNEL ($(stat -c%s "$KERNEL") bytes)"

fi

echo "== The start hook =="
# The hook exists to keep an EXTERNAL kernel in step with the image. A domain
# that IPLs has no such copy to keep current, and a hook that rewrites a file
# nothing reads is a thing to explain to the next reader for no reason.
if [ -z "$EL_EXTERNAL_KERNEL" ]; then
    # An earlier run may have left one, refreshing a file this domain no
    # longer boots. Removing ours is tidying; another author's is not ours.
    if [ -e "$HOOK" ] && grep -q "libvirt-hook" "$HOOK" 2>/dev/null; then
        sudo rm -f "$HOOK"
        say "removed: the domain IPLs, the hook had nothing left to refresh"
    else
        say "not installed: an IPL domain has no external kernel to refresh"
    fi
elif [ -e "$HOOK" ] && ! grep -q "libvirt-hook" "$HOOK" 2>/dev/null; then
    die "$HOOK exists and is not ours -- refusing to overwrite it"
else
    substitute "$TPL/qemu-hook.sh.in" | sudo tee "$HOOK" >/dev/null
    sudo chmod 0755 "$HOOK"
    say "$HOOK installed, inert for every domain but $NAME"
fi

echo "== The domain =="
tmp="$(mktemp)"
substitute "$TPL/arch-s390x.xml.in" > "$tmp"
# REDEFINING KEEPS THE UUID. The template carries none, so libvirt would mint a
# fresh one and then refuse the definition -- `domain 'arch-s390x' already
# exists with uuid ...` -- because the name is taken by what is, to libvirt, a
# different machine. Re-running this script is the normal way to change the
# domain, so it has to be the case that works.
# THE FIRST INSTALL IS THE ONE THAT HAS NO UUID TO KEEP.
#
# `virsh domuuid` exits non-zero when the domain is unknown, and under
# `set -o pipefail` that failure becomes the pipeline's, which `set -e`
# turns into the end of the script -- silently, one line before `define`.
# A guard that preserves an existing identity must tolerate there being
# none yet, or the script can only ever redefine, never install.
_uuid="$(virsh --connect "$CONNECT" domuuid "$NAME" 2>/dev/null | tr -d '[:space:]' || true)"
if [ -n "$_uuid" ]; then
    sed -i "s|<name>$NAME</name>|<name>$NAME</name>\n  <uuid>$_uuid</uuid>|" "$tmp"
    say "keeping uuid ${_uuid%%-*}…"
fi
# AND THE MAC, for the same reason one step further. The template names none,
# so a redefinition mints a fresh one, DHCP hands out a different lease, and
# every ssh config and bookmark pointing at the guest is wrong -- a redefine
# that moves the machine is a redefine nobody dares run.
_mac="$(virsh --connect "$CONNECT" dumpxml --inactive "$NAME" 2>/dev/null \
        | grep -o "mac address='[^']*'" | head -1 | cut -d"'" -f2 || true)"
if [ -n "$_mac" ]; then
    sed -i "s|<interface type='network'>|<interface type='network'>\n      <mac address='$_mac'/>|" "$tmp"
    say "keeping mac $_mac"
fi
virsh --connect "$CONNECT" define "$tmp" >/dev/null
virsh --connect "$CONNECT" autostart "$NAME" >/dev/null
say "$NAME defined and set to autostart"

cat <<EOF

  virsh --connect $CONNECT start $NAME
  virsh --connect $CONNECT console $NAME      # Ctrl-] to detach
  virsh --connect $CONNECT domifaddr $NAME    # the address DHCP handed out
EOF
