#!/usr/bin/env bash
# Point the guest's pacman at the repository this port actually has.
#
# Runs INSIDE the guest, as root. Takes host:port -- the address
# scripts/serve-repo.sh prints on the host.
#
# WHAT IT REPAIRS. A guest installed with `pacman --root` inherits Arch's stock
# /etc/pacman.conf: [core] and [extra], both including a mirrorlist that is
# EMPTY, because no Arch mirror carries s390x. pacman then answers
# `no servers configured for repository` to every request -- it is not broken,
# it has nowhere to look.
#
# WHY [extra] GOES. This port builds one repository. A pacman.conf naming a
# repository that will never exist makes every -Sy print a failure that means
# nothing, and teaches the reader to ignore failures.
#
# WHY SigLevel = Never ON THIS REPOSITORY. Nothing in this port is signed --
# makepkg runs with PGP checks off, because the PKGBUILDs are patched here and
# upstream signatures cannot match a modified source list. Arch's stock
# SigLevel then makes pacman ask for a .sig that was never produced and fail
# the whole transaction on a 404. The trust this drops is real and it is
# recorded in TODO.md; what replaces it is that the repository is served from
# the machine that built it, over a bridge only its own guests can reach.
#
# WHY THE EDIT IS LINE BY LINE. A regex that deleted from `[extra]` to the next
# `[` swallowed the `#` in front of `#[multilib-testing]` and ACTIVATED it --
# a section commented out for good reason, turned on by an edit aimed at its
# neighbour. Sections are lines; they are edited as lines.
set -euo pipefail

SERVER="${1:-}"
VERIFY="${2:-}"
[ -n "$SERVER" ] || {
    echo "usage: $(basename "$0") <host:port> [--verify]" >&2; exit 1; }
[ "$(id -u)" = 0 ] || { echo "must run as root in the guest" >&2; exit 1; }

MIRROR=/etc/pacman.d/mirrorlist
CONF=/etc/pacman.conf

# The first run keeps the stock file; later runs start from it again, so this
# script is idempotent instead of cumulative.
if [ -f "$CONF.before-s390x" ]; then
    cp "$CONF.before-s390x" "$CONF"
else
    cp "$CONF" "$CONF.before-s390x"
fi

cat > "$MIRROR" <<EOF
# The stage-2 repository, served by the host that runs this guest. No Arch
# mirror publishes s390x; this is the only one there is.
Server = http://$SERVER/s390x
EOF

python3 - "$CONF" <<'PY'
import io, sys

path = sys.argv[1]
out, dropping = [], False
for line in io.open(path, encoding="utf-8"):
    stripped = line.strip()
    # A section header, and only a real one: a commented line is text.
    if stripped.startswith("[") and stripped.endswith("]"):
        dropping = stripped == "[extra]"
    if not dropping:
        out.append(line)
io.open(path, "w", encoding="utf-8").write("".join(out))
PY

grep -q '^\[core\]' "$CONF" || printf '\n[core]\nInclude = %s\n' "$MIRROR" >> "$CONF"

# --verify : take the port's own key into pacman's keyring, and REQUIRE a
# signature from it. Without it, SigLevel stays Never and the guest installs
# whatever the repository hands it.
#
# WHY THE KEY IS SIGNED LOCALLY. pacman does not trust a key because it is
# present; it trusts one that the local keyring has signed. `--lsign-key` is
# that act, and it is the step whose absence produces `signature is marginal
# trust` on every install -- a message that names the symptom and not the
# missing command.
SIGLEVEL="Never"
if [ "$VERIFY" = "--verify" ]; then
    # La mirrorlist vise <serveur>/s390x ; la clé est à la racine servie,
    # à côté du répertoire d'architecture.
    curl -fsS "http://$SERVER/arch-s390x-port.pub" -o /tmp/port.pub \
        || { echo "public key not served by $SERVER" >&2; exit 1; }
    [ -s /tmp/port.pub ] || { echo "public key is empty" >&2; exit 1; }
    pacman-key --list-keys >/dev/null 2>&1 || pacman-key --init
    pacman-key --add /tmp/port.pub
    _fpr="$(gpg --show-keys --with-colons /tmp/port.pub \
            | awk -F: '/^fpr:/ {print $10; exit}')"
    [ -n "$_fpr" ] || { echo "cannot read the key fingerprint" >&2; exit 1; }
    pacman-key --lsign-key "$_fpr"
    rm -f /tmp/port.pub
    SIGLEVEL="Required DatabaseRequired"
    echo "  key $_fpr trusted locally"
fi

# SigLevel belongs to the section, and the stock [core] does not carry one --
# it inherits the global default, which requires a signature.
python3 - "$CONF" "$SIGLEVEL" <<'PY'
import io, sys

path, siglevel = sys.argv[1], sys.argv[2]
out, in_core, done = [], False, False
for line in io.open(path, encoding="utf-8"):
    stripped = line.strip()
    if stripped.startswith("[") and stripped.endswith("]"):
        if in_core and not done:
            out.append("SigLevel = %s\n" % siglevel)
            done = True
        in_core = stripped == "[core]"
    if stripped.startswith("SigLevel") and in_core:
        continue
    out.append(line)
if in_core and not done:
    out.append("SigLevel = %s\n" % siglevel)
io.open(path, "w", encoding="utf-8").write("".join(out))
PY

echo "== Repositories =="
grep -E '^\[' "$CONF" | tr -d '[]' | sed 's/^/  /'
echo "== Synchronising =="
# La base en cache PART avant la synchronisation. Elle a pu être posée quand
# SigLevel valait encore Never -- c'est le cas dans une image, dont les
# paquets sont installés avant que ce script ne passe -- et elle n'a alors
# aucun .sig à côté d'elle. pacman la lit, la refuse, la retélécharge et
# finit bien, en ayant affiché `error: core: missing required signature` au
# passage. Le résultat était juste et le message disait le contraire.
rm -f /var/lib/pacman/sync/*.db /var/lib/pacman/sync/*.db.sig
pacman -Syy
echo "== Available =="
printf '  %s packages, SigLevel = %s\n' "$(pacman -Slq core | wc -l)" "$SIGLEVEL"
