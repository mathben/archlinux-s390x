#!/usr/bin/env bash
# Produce a distributable ERPLibre image: build the base, install ERPLibre in
# a booted guest, then take the machine's identity back out of it.
#
# WHY A BOOTED GUEST AND NOT A chroot. provision-erplibre.sh starts postgresql
# and odoo as systemd units and reads back /web/login over HTTP: a chroot has
# no PID 1 and shares the host's network, so what it would prove is not what a
# deployed machine does. This drives the real thing, over ssh, and the guest is
# shut down cleanly before the image is touched again.
#
# WHY THE IDENTITY IS STRIPPED AT THE END. Everything installed here is
# identical on every copy -- that is the point. What must NOT be identical is
# what identifies a machine: ssh host keys, the machine-id systemd derives
# journal and DHCP identity from, the guest's own logs. An image published with
# host keys in it hands every deployment the same fingerprint, and the second
# machine to boot is indistinguishable from the first.
#
# WHAT IS DELIBERATELY KEPT: the odoo_erplibre database, the Python
# environment, the cloned sources. They ARE the product; regenerating them is
# the hour this script exists to spend once.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="${WORK:-$HOME/work/arch-s390x}"
OUT="${OUT:-$WORK/erplibre-s390x.img}"
BASE_MNT="${BASE_MNT:-$WORK/mnt-erplibre-image}"
SSH_PORT="${SSH_PORT:-2224}"
HTTP_PORT="${HTTP_PORT:-8071}"
VM_MEM="${VM_MEM:-6144}"
VM_CPUS="${VM_CPUS:-4}"
EL_SSH_KEY="${EL_SSH_KEY:-$HOME/.ssh/vm_s390x}"
EL_REPO_SERVER="${EL_REPO_SERVER:-}"
CONSOLE="$WORK/erplibre-image-console.txt"
PIDFILE="$WORK/erplibre-image.pid"
LOG="$WORK/erplibre-image-provision.txt"

die() { echo "build-erplibre-image: $*" >&2; exit 1; }
say() { printf '  %s\n' "$*"; }
step() { printf '\n== %s ==\n' "$*"; }

[ -f "$EL_SSH_KEY" ] || die "no ssh key at $EL_SSH_KEY"
[ -f "$HERE/build-image.sh" ] || die "build-image.sh is missing"
[ -f "$HERE/provision-erplibre.sh" ] || die "provision-erplibre.sh is missing"
[ -e "$OUT" ] && die "$OUT exists -- move it aside first"

guest() {
    ssh -p "$SSH_PORT" -i "$EL_SSH_KEY" \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o BatchMode=yes -o ConnectTimeout=10 root@127.0.0.1 "$@"
}

stop_guest() {
    [ -s "$PIDFILE" ] || return 0
    guest "systemctl poweroff" 2>/dev/null || true
    for _ in $(seq 1 60); do
        kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null || return 0
        sleep 2
    done
    # A guest that will not go down cleanly must not be packaged: the
    # filesystem it leaves behind was never synced.
    die "the guest did not shut down; the image is NOT usable as it stands"
}
trap 'stop_guest' EXIT

step "1/5 Base image"
IMG="$OUT" MNT="$BASE_MNT" EL_SSH_PUBKEY="$EL_SSH_KEY.pub" \
    EL_REPO_SERVER="$EL_REPO_SERVER" HOSTNAME_=erplibre \
    bash "$HERE/build-image.sh"

step "2/5 Boot"
IMG="$OUT" KERNEL= CONSOLE="$CONSOLE" PIDFILE="$PIDFILE" \
    SSH_PORT="$SSH_PORT" HTTP_PORT="$HTTP_PORT" \
    VM_MEM="$VM_MEM" VM_CPUS="$VM_CPUS" \
    bash "$HERE/run-vm.sh" detach
for i in $(seq 1 60); do
    guest true 2>/dev/null && break
    sleep 5
done
guest true 2>/dev/null || die "the guest never answered on port $SSH_PORT"
say "up: $(guest 'uname -r') / $(guest 'systemctl is-system-running' || true)"

step "3/5 ERPLibre"
# Long -- pyenv compiles CPython, pip compiles four Rust extensions. Run it
# detached inside the guest so a dropped ssh link does not kill it.
scp -P "$SSH_PORT" -i "$EL_SSH_KEY" -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -q \
    "$HERE/provision-erplibre.sh" root@127.0.0.1:/root/
# The exit status is APPENDED TO THE LOG by the guest itself. Asking /proc
# whether the script is still running does not work from here: the ssh command
# carrying the question has the searched-for name in its own command line, and
# matches itself. A marker in the file answers without that trap.
guest "setsid nohup sh -c 'bash /root/provision-erplibre.sh; echo \"__PROVISION_EXIT=\$?\"' > /root/provision.log 2>&1 < /dev/null & disown" || true
: > "$LOG"
while :; do
    sleep 60
    guest "cat /root/provision.log" > "$LOG" 2>/dev/null || continue
    tail -1 "$LOG" | sed 's/^/  /'
    if grep -q "__PROVISION_EXIT=0" "$LOG"; then
        break
    elif grep -q "__PROVISION_EXIT=" "$LOG"; then
        die "provisioning failed ($(grep -o '__PROVISION_EXIT=[0-9]*' "$LOG" | tail -1)); see $LOG"
    fi
done
say "ERPLibre answers on the guest's own port"

step "4/5 Shut down"
stop_guest
trap - EXIT
say "clean shutdown"

step "5/5 Strip the machine identity"
sudo mkdir -p "$BASE_MNT"
sudo mount -o loop "$OUT" "$BASE_MNT"
trap 'sudo umount "$BASE_MNT" 2>/dev/null || true' EXIT
# ssh host keys: regenerated at first boot, and every copy sharing one set
# would present the same fingerprint to every client.
sudo rm -f "$BASE_MNT"/etc/ssh/ssh_host_*
say "ssh host keys removed (regenerated on first boot)"
# machine-id EMPTY, not absent: systemd treats an empty file as "first boot"
# and writes a new id, where a missing one makes it complain. The journal and
# the DHCP client identifier both derive from it.
sudo truncate -s 0 "$BASE_MNT/etc/machine-id"
say "machine-id emptied"
# The guest's own history, not the product's.
sudo rm -rf "$BASE_MNT"/var/log/journal/* "$BASE_MNT"/root/.bash_history \
    "$BASE_MNT"/root/provision.log "$BASE_MNT"/root/provision-erplibre.sh
sudo rm -rf "$BASE_MNT"/var/cache/pacman/pkg/*
say "logs, history and package cache cleared"
# The key that drove the build is not the key of whoever deploys the image.
sudo rm -f "$BASE_MNT/root/.ssh/authorized_keys"
say "build key removed -- deploy with --ssh-key"
sudo umount "$BASE_MNT"
trap - EXIT

say "image ready: $OUT ($(du -sh "$OUT" | cut -f1) on disk)"
cat <<EOF

  Deploy it:
    EL_LOCAL_IMAGE=$OUT python3 script/qemu/deploy_qemu.py \\
      --distro arch --arch s390x --name <nom> --hostname <nom> \\
      --ssh-key ~/.ssh/<clé>.pub

EOF
