#!/usr/bin/env bash
# Sign the stage-2 repository with a key of this port's own.
#
# WHAT THIS REPLACES. Guests read the repository with `SigLevel = Never`,
# because nothing was signed and Arch's stock setting makes pacman demand a
# .sig that never existed. That works and it verifies nothing: anything that
# can write into the repository directory, or answer on the HTTP port, is
# installed as root by every guest.
#
# WHY NOT archlinux-keyring. Arch's developers signed none of these packages --
# they were all built here, from patched PKGBUILDs. Shipping their keyring
# would put an apparatus of verification on a system where nothing they signed
# exists. The key that belongs here is the one that built the packages.
#
# WHERE THE PRIVATE KEY LIVES, AND WHAT THAT COSTS. In a GnuPG home under the
# WORK directory, never in the repository -- a signing key in git is a signing
# key published. It has NO PASSPHRASE, which is a deliberate trade: two hundred
# and seventy-seven signatures cannot each wait for a human, and a build that
# stops halfway through signing leaves a repository in two states. What the
# signature then proves is that a package came from this build host and reached
# the guest unaltered. What it does not prove is that nobody with an account on
# this host made it. Both halves are true and the second is not a detail.
set -euo pipefail

WORK="${WORK:-$HOME/work/arch-s390x}"
REPO2="${REPO2:-$WORK/repo2/s390x}"
export GNUPGHOME="${GNUPGHOME:-$WORK/gnupg}"
KEY_UID="${KEY_UID:-Arch s390x port (package signing) <port@localhost>}"
PUBKEY="${PUBKEY:-$WORK/repo2/arch-s390x-port.pub}"
DB="${DB:-core.db.tar.gz}"

die() { echo "sign-repo: $*" >&2; exit 1; }
say() { printf '  %s\n' "$*"; }

command -v gpg >/dev/null || die "gnupg is not installed"
command -v repo-add >/dev/null || die "repo-add is not in PATH"
[ -d "$REPO2" ] || die "no repository at $REPO2"

echo "== The key =="
if [ ! -d "$GNUPGHOME" ]; then
    mkdir -p "$GNUPGHOME"
    chmod 700 "$GNUPGHOME"
    # --batch with an empty passphrase: see the header. ed25519 rather than
    # RSA because pacman verifies with it and the signatures are a quarter the
    # size, across two hundred and seventy-seven files.
    gpg --batch --quiet --passphrase "" --quick-generate-key "$KEY_UID" \
        ed25519 sign never
    say "generated in $GNUPGHOME"
else
    say "existing key in $GNUPGHOME"
fi
FPR="$(gpg --list-secret-keys --with-colons "$KEY_UID" \
       | awk -F: '/^fpr:/ {print $10; exit}')"
[ -n "$FPR" ] || die "no secret key for $KEY_UID"
say "fingerprint $FPR"

echo "== Signatures =="
signed=0 already=0
for pkg in "$REPO2"/*.pkg.tar.zst; do
    [ -e "$pkg" ] || continue
    if [ -f "$pkg.sig" ] && gpg --verify "$pkg.sig" "$pkg" 2>/dev/null; then
        already=$((already + 1)); continue
    fi
    # --yes: a stale .sig from an earlier key must be replaced, not kept.
    gpg --batch --yes --quiet --detach-sign --no-armor \
        --local-user "$FPR" "$pkg"
    signed=$((signed + 1))
done
say "$signed signed, $already already valid"

echo "== Database =="
# LA SIGNATURE DE LA BASE PART D ABORD. `repo-add -v` verifie la signature de
# la base EXISTANTE avant d en ecrire une nouvelle -- et une base reecrite par
# une construction porte justement une signature qui ne correspond plus. Le
# garde refusait alors l ecriture, donc refusait la reparation :
#
#   gpg: assuming signed data in 'core.db.tar.gz'
#   (et le .sig reste celui de la veille)
#
# Ce qui doit etre verifie, ce sont les PAQUETS ; la base, elle, est refaite.
rm -f "$REPO2/$DB.sig" "$REPO2/${DB%%.*}.db.sig" \
      "$REPO2/${DB%%.*}.files.tar.gz.sig" "$REPO2/${DB%%.*}.files.sig"
# repo-add -s signe la base ; -v verifie la signature de chaque paquet ajoute,
# ce qui fait d un repertoire de fichiers un depot dont l index ne peut pas
# etre echange par-dessous.
( cd "$REPO2" && repo-add -q -s -v -k "$FPR" "$DB" ./*.pkg.tar.zst >/dev/null )
say "$DB rebuilt and signed"

echo "== Public key =="
mkdir -p "$(dirname "$PUBKEY")"
gpg --batch --yes --export --armor "$FPR" > "$PUBKEY"
say "$PUBKEY ($(wc -l < "$PUBKEY") lines)"
cat <<EOF

  In a guest, once it can reach the repository:

    bash scripts/setup-guest-pacman.sh <host:port> --verify

  which fetches that key, signs it locally in pacman's own keyring, and
  raises SigLevel. Without --verify the guest keeps SigLevel = Never.

EOF
