#!/usr/bin/env bash
# Serve the stage-2 repository to the guests, over HTTP on the NAT bridge.
#
# WHY A GUEST NEEDS THIS AT ALL. No Arch mirror publishes s390x, so a guest
# booted from this port has an EMPTY mirrorlist: pacman runs and can install
# nothing, upgrade nothing, and answer no dependency. The only repository that
# exists for this architecture is the one on this host.
#
# WHY STAGE 2 ONLY, AND NEVER STAGE 1. Stage-1 packages were compiled against
# Ubuntu's libraries -- that is what stage 2 exists to dissolve. Serving them
# to a target would reintroduce, one package at a time, the exact contamination
# the port spent its whole bootstrap removing. A package the guest needs and
# stage 2 does not have is a package to BUILD, not to borrow.
#
# WHY THE BRIDGE ADDRESS AND NOT 0.0.0.0. The libvirt NAT bridge is reachable
# by the guests and by this host, and by nothing else. This machine is shared;
# an unauthenticated file server on all its interfaces is not a detail.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="${WORK:-$HOME/work/arch-s390x}"
REPO2="${REPO2:-$WORK/repo2}"
NETWORK="${NETWORK:-default}"
PORT="${PORT:-8081}"
UNIT="${UNIT:-arch-s390x-repo}"
SERVICE="/etc/systemd/system/$UNIT.service"

die() { echo "serve-repo: $*" >&2; exit 1; }
say() { printf '  %s\n' "$*"; }

[ -d "$REPO2/s390x" ] || die "no stage-2 repository at $REPO2/s390x"

# The address libvirt gave the bridge, asked rather than assumed: a network
# redefined on another host has another subnet.
bridge_addr() {
    local br
    br="$(virsh --connect qemu:///system net-info "$NETWORK" 2>/dev/null | awk '/Bridge/{print $2}')"
    [ -n "$br" ] || die "libvirt network '$NETWORK' has no bridge"
    ip -4 -brief addr show "$br" | awk '{print $3}' | cut -d/ -f1
}

case "${1:-status}" in
    install)
        ADDR="$(bridge_addr)"
        [ -n "$ADDR" ] || die "the bridge has no address; is the '$NETWORK' network started?"
        # python3 -m http.server is enough for a package repository: pacman
        # asks for files by name and validates them itself. A real web server
        # here would be one more thing to configure on a shared host.
        sudo tee "$SERVICE" >/dev/null <<UNITFILE
[Unit]
Description=Arch s390x stage-2 package repository
After=network-online.target libvirtd.service
Wants=network-online.target

[Service]
ExecStart=$(command -v python3) -m http.server $PORT --bind $ADDR --directory $REPO2
Restart=on-failure
# Read-only by construction: http.server serves GET and nothing else, and this
# user owns the tree it is handing out.
User=$(id -un)
Group=$(id -gn)

[Install]
WantedBy=multi-user.target
UNITFILE
        sudo systemctl daemon-reload
        sudo systemctl enable --now "$UNIT"
        say "$UNIT serving $REPO2 on $ADDR:$PORT"
        cat <<EOF

  In the guest, once it can reach $ADDR:

    bash scripts/setup-guest-pacman.sh $ADDR:$PORT

EOF
        ;;
    status)
        systemctl is-active "$UNIT" >/dev/null 2>&1 \
            && say "$UNIT active on $(bridge_addr):$PORT" \
            || say "$UNIT is not running"
        ls "$REPO2"/s390x/*.pkg.tar.zst 2>/dev/null | wc -l | xargs -I{} echo "  {} packages in $REPO2/s390x"
        ;;
    stop)
        sudo systemctl disable --now "$UNIT" && say "$UNIT stopped"
        ;;
    *)
        die "usage: $(basename "$0") [install|status|stop]"
        ;;
esac
