#!/usr/bin/env bash
# Build a bootable deployment image from the stage-2 repository.
#
# WHAT THIS REPLACES. The image that runs today was populated by hand: a mkfs,
# a mount, a `pacman --root`, and a dozen edits under /etc typed one at a time.
# It works and nobody can reproduce it, which is the same as not having it. The
# fifty-one packages below are what that image actually holds, read back from
# it with `pacman -Qqe` rather than remembered.
#
# WHY A chroot IS ALLOWED HERE. `pacman --root` does NOT run install scriptlets
# -- the reason a hand-built image shipped with an empty CA bundle and every
# TLS client failing on `error adding trust anchors`. This host is s390x, so
# the guest's own binaries run on it natively and a chroot closes that gap
# instead of leaving work for first boot.
#
# WHAT IT REFUSES TO DO. Set a root password of its own invention, or bake in a
# public key it found lying about. Both come from the environment or the image
# ships without them: an image with a password somebody else chose is worse
# than an image with none.
#
# THE IMAGE IS SPARSE. 24 GiB of address space costs what the files in it
# actually take -- five gigabytes for a working ERPLibre. Do not "save space"
# by shrinking it; ERPLibre's addons and a PostgreSQL cluster grow into it.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="${WORK:-$HOME/work/arch-s390x}"
IMG="${IMG:-$WORK/arch-s390x.img}"
MNT="${MNT:-$WORK/mnt-image}"
CONF="${CONF:-$WORK/pacman-test.conf}"
CACHE="${CACHE:-$WORK/pacman-el.cache}"
SIZE="${SIZE:-24G}"
LABEL="${LABEL:-ARCH_S390X}"
HOSTNAME_="${HOSTNAME_:-arch-s390x}"
# Optional, and deliberately without defaults -- see the header.
EL_SSH_PUBKEY="${EL_SSH_PUBKEY:-}"
EL_ROOT_PASSWORD="${EL_ROOT_PASSWORD:-}"
EL_REPO_SERVER="${EL_REPO_SERVER:-}"
# cloud-init: absent by default. An image that carries it behaves like every
# other cloud image -- a deployment hands it a cidata seed and it applies
# hostname, users and keys at first boot. An image without it is configured
# here, once, and boots already set up. Both are legitimate; the second is
# smaller and starts faster, the first is what a cloud expects.
EL_CLOUD_INIT="${EL_CLOUD_INIT:-}"
# Vérifier les signatures du dépôt plutôt que de faire confiance au réseau.
# Demande que scripts/sign-repo.sh ait tourné : sans clé publique servie, le
# réglage ferait échouer le premier pacman de l'image.
EL_VERIFY_REPO="${EL_VERIFY_REPO:-}"

# What the image holds. Explicit packages only: pacman pulls the rest, and a
# list that names dependencies goes stale the day one of them changes.
PKGS=(
    # A system that boots and can be logged into. s390-tools is zipl, which
    # writes the boot record: without it the image is a filesystem that some
    # other machine has to hand a kernel to.
    filesystem glibc bash coreutils systemd systemd-sysvcompat shadow util-linux
    linux s390-tools openssh sudo inetutils which
    # Files, archives, text.
    sed grep gawk findutils diffutils file tar xz bzip2 zlib patch e2fsprogs
    # The toolchain ERPLibre compiles CPython and its wheels with.
    base-devel gcc binutils make cmake pkgconf swig rust git curl wget
    # What pyenv's CPython links against, and what Odoo's wheels need.
    openssl readline sqlite libffi ncurses gdbm libxml2 libxslt
    libjpeg-turbo qpdf openldap libsasl
    # The database, and the interpreter this port carries for pacman and meson.
    postgresql python
    # pacman itself: an image that cannot install a package is not a system.
    pacman
)

die() { echo "build-image: $*" >&2; exit 1; }
say() { printf '  %s\n' "$*"; }

[ -f "$CONF" ] || die "no pacman configuration at $CONF"
command -v mkfs.ext4 >/dev/null || die "e2fsprogs is not installed on the host"
[ "$(uname -m)" = s390x ] || die "the chroot step needs an s390x host"

# Bind mounts inside a tree that gets removed have already followed into the
# host's /dev once in this project. Everything unmounts through one trap, in
# reverse order, whatever happens.
CLEANUP=()
cleanup() {
    local i
    for (( i=${#CLEANUP[@]}-1 ; i>=0 ; i-- )); do
        sudo umount "${CLEANUP[i]}" 2>/dev/null || true
    done
    sudo umount "$MNT" 2>/dev/null || true
}
trap cleanup EXIT

if [ -e "$IMG" ]; then
    die "$IMG exists -- move it aside; this script does not overwrite an image"
fi

echo "== The filesystem =="
truncate -s "$SIZE" "$IMG"
mkfs.ext4 -q -F -L "$LABEL" "$IMG"
say "$SIZE sparse, ext4, LABEL=$LABEL"

sudo mkdir -p "$MNT"
sudo mount -o loop "$IMG" "$MNT"
say "mounted on $MNT"

if [ -n "$EL_CLOUD_INIT" ]; then
    PKGS+=(cloud-init)
fi

echo "== Packages =="
# alpm refuses to initialise against a database directory that does not exist,
# and --root creates neither. On a freshly formatted image there is nothing
# but lost+found.
sudo mkdir -p "$MNT/var/lib/pacman" "$MNT/var/cache/pacman/pkg"
sudo pacman --config "$CONF" --root "$MNT" --cachedir "$CACHE" --noconfirm -Sy "${PKGS[@]}" \
    >/dev/null || die "pacman failed; run it by hand to see why"
say "$(sudo ls "$MNT/var/lib/pacman/local" | wc -l) packages installed"

echo "== Configuration =="
sudo tee "$MNT/etc/fstab" >/dev/null <<EOF
# The root is found by LABEL, not by /dev/vda: a second disk, or a different
# bus order, renames the device and not the label.
LABEL=$LABEL  /  ext4  rw,relatime  0 1
EOF
echo "$HOSTNAME_" | sudo tee "$MNT/etc/hostname" >/dev/null
echo "LANG=C.UTF-8" | sudo tee "$MNT/etc/locale.conf" >/dev/null
sudo mkdir -p "$MNT/etc/systemd/network"
sudo tee "$MNT/etc/systemd/network/20-wired.network" >/dev/null <<'EOF'
# enc* is what a virtio NIC on the CCW bus is called; en* covers it and the
# names any other transport would produce.
[Match]
Name=en*

[Network]
DHCP=yes
EOF
# resolved, and the symlink it is useless without. networkd learns the DNS
# server over DHCP and writes it where resolved reads it; nothing writes
# /etc/resolv.conf, so without this link the guest has addresses and no names
# -- `Could not resolve host` on the first pip or git clone.
sudo systemctl --root="$MNT" enable systemd-networkd systemd-resolved sshd >/dev/null
if [ -n "$EL_CLOUD_INIT" ]; then
    # Arch ships cloud-init's units DISABLED, and an image with the package but
    # not the units reads no seed at all -- the deployment would look like it
    # applied nothing. All four, because they run at four different points of
    # the boot and each depends on the ones before it.
    sudo systemctl --root="$MNT" enable \
        cloud-init-local.service cloud-init-main.service \
        cloud-config.service cloud-final.service >/dev/null
    say "cloud-init: package and its four units enabled"
fi
sudo ln -sf ../run/systemd/resolve/stub-resolv.conf "$MNT/etc/resolv.conf"
say "fstab, hostname, locale, DHCP on en*, networkd, resolved and sshd enabled"

echo "== Scriptlets pacman --root skipped =="
for d in dev proc sys; do
    sudo mount --bind "/$d" "$MNT/$d"
    CLEANUP+=("$MNT/$d")
done
# System users and the directories they own. On a running system systemd does
# this at boot; in a fresh image nobody has, and the absence is not subtle:
# pacman itself refuses to start -- `problem setting DownloadUser 'alpm'` --
# and postgres has no account to run initdb under.
sudo chroot "$MNT" /usr/bin/systemd-sysusers >/dev/null
sudo chroot "$MNT" /usr/bin/systemd-tmpfiles --create >/dev/null 2>&1 || true
say "system users: $(sudo grep -cE '^(alpm|postgres|nobody):' "$MNT/etc/passwd") of alpm, postgres, nobody"

# The CA bundle: 121 certificates that exist as files and are not assembled
# until something says so. Without this the image cannot speak TLS at all.
sudo chroot "$MNT" /usr/bin/update-ca-trust
say "CA bundle: $(sudo grep -c 'BEGIN CERTIFICATE' "$MNT/etc/ca-certificates/extracted/tls-ca-bundle.pem") certificates"
# Host keys, so the first boot does not hand out a fresh identity under time
# pressure -- and so sshd starts at all.
sudo chroot "$MNT" /usr/bin/ssh-keygen -A >/dev/null
say "ssh host keys: $(sudo ls "$MNT"/etc/ssh/ssh_host_*_key 2>/dev/null | wc -l)"

if [ -n "$EL_REPO_SERVER" ]; then
    sudo cp "$HERE/setup-guest-pacman.sh" "$MNT/tmp/"
    sudo chroot "$MNT" /bin/bash /tmp/setup-guest-pacman.sh \
        "$EL_REPO_SERVER" ${EL_VERIFY_REPO:+--verify} >/dev/null
    sudo rm -f "$MNT/tmp/setup-guest-pacman.sh"
    say "pacman points at $EL_REPO_SERVER${EL_VERIFY_REPO:+, signatures required}"
else
    say "no EL_REPO_SERVER given: the guest ships with no repository"
fi

echo "== Boot record =="
# WHY THE KERNEL IS COPIED INTO /boot. The linux package puts it under
# /usr/lib/modules/<version>/, where an Arch system's boot loader hook would
# find it. There is no such hook here, and zipl reads the path it is given.
_kver="$(sudo ls "$MNT/usr/lib/modules" | head -1)"
[ -n "$_kver" ] || die "no kernel under /usr/lib/modules in the image"
sudo install -Dm644 "$MNT/usr/lib/modules/$_kver/vmlinuz" "$MNT/boot/vmlinuz-linux"
# root=/dev/vda, not root=LABEL=: resolving a label is udev's work, and udev
# lives in an initramfs this image deliberately does not have. The device name
# is the guest's, not this host's -- zipl records block addresses, and the loop
# device it writes through maps one to one onto the file.
sudo tee "$MNT/etc/zipl.conf" >/dev/null <<EOF
[defaultboot]
default=arch

[arch]
target=/boot
image=/boot/vmlinuz-linux
parameters="root=/dev/vda rw console=ttysclp0"
EOF
# WHY THE COMMAND LINE AND NOT zipl.conf. Reading its config, zipl asks the
# kernel for the geometry of the device holding /boot and stops on a loop
# device -- `Error: Could not get disk geometry`. The --target* options exist
# for exactly this: installing onto a device that is not the one running. The
# geometry is not guessed, it is declared: a plain SCSI-scheme disk, 512-byte
# blocks, no partition table, no offset.
#
# The zipl.conf written above is for the GUEST, where `zipl` after a kernel
# upgrade must work with no arguments; it deliberately names no targetbase,
# because the loop device belongs to this host and not to the image.
_loop="$(losetup -j "$IMG" | head -1 | cut -d: -f1)"
[ -n "$_loop" ] || die "cannot find the loop device backing $IMG"
sudo chroot "$MNT" /usr/bin/zipl \
    --image=/boot/vmlinuz-linux \
    --parameters="root=/dev/vda rw console=ttysclp0" \
    --target=/boot --targetbase="$_loop" \
    --targettype=SCSI --targetblocksize=512 --targetoffset=0 \
    >/dev/null || die "zipl failed to write the boot record"
say "zipl: $_kver, IPL from the disk itself"

echo "== Root access =="
if [ -n "$EL_SSH_PUBKEY" ]; then
    [ -f "$EL_SSH_PUBKEY" ] || die "no public key at $EL_SSH_PUBKEY"
    sudo install -d -m 0700 "$MNT/root/.ssh"
    sudo install -m 0600 "$EL_SSH_PUBKEY" "$MNT/root/.ssh/authorized_keys"
    say "authorized_keys from $(basename "$EL_SSH_PUBKEY")"
else
    say "no EL_SSH_PUBKEY given: no key installed"
fi
if [ -n "$EL_ROOT_PASSWORD" ]; then
    echo "root:$EL_ROOT_PASSWORD" | sudo chroot "$MNT" /usr/bin/chpasswd
    say "root password set"
else
    # Not the same as an empty password: with no key either, the console asks
    # for something nothing can answer.
    say "no EL_ROOT_PASSWORD given: the serial console cannot log in"
fi

cleanup
trap - EXIT
say "image ready: $IMG ($(du -sh "$IMG" | cut -f1) on disk, $SIZE apparent)"
