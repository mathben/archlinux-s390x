#!/usr/bin/env bash
# Refuse to carry the developer's machine in the repository.
#
# WHY THIS EXISTS. RELAIS.md was written with the build machine's ssh alias, the
# guest's IP address, and the author's name and e-mail in the body of the text.
# None of it was needed: a successor needs the SHAPE of the access, not its
# coordinates, and the commit identity is already in the author field of every
# commit.
#
# It is a check rather than a one-time cleanup because the leak arrives by
# accident. Every path in this port gets pasted from a terminal at some point --
# error messages carry absolute paths, and absolute paths carry usernames.
#
# Run over the TRACKED files only. Build output under work/ is nobody's business
# here and is not versioned; see scripts/upstream-lock.sh for what is.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

# Deliberately narrow. A pattern that fires on ordinary prose gets disabled, and
# a disabled check is worse than none.
#
#   - RFC1918 addresses and any dotted quad
#   - /home/<name>, which is how a username travels
#   - an e-mail address
declare -a PATTERNS=(
    '\b10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\b'
    '\b192\.168\.[0-9]{1,3}\.[0-9]{1,3}\b'
    '\b172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}\b'
    '/home/[a-z][a-z0-9_-]*'
)
# 127.0.0.0/8 is NOT here. It was, and it flagged
#
#   scripts/create-rootfs.sh:152   127.0.0.1  localhost
#   scripts/create-rootfs.sh:154   127.0.1.1  archlinux-s390x.localdomain
#
# which is the content an /etc/hosts is supposed to have. Loopback says nothing
# about whose machine this is -- that is the whole point of loopback -- and a
# check that fails on a correct file is a check somebody will stop running.
declare -a NAMES=(
    'address'
    'private address'
    'private address'
    'home directory with a username'
)
# NO GENERIC E-MAIL PATTERN. There was one, and it had to go on its first run:
#
#   scripts/create-rootfs.sh:302   .../etc/systemd/system/getty@tty1.service
#   CODEOWNERS:4                   * @Morganamilo morganamilo@archlinux.org
#   arch-kernel/PKGBUILD-s390x:1   # Maintainer: ... <heftig@archlinux.org>
#
# A systemd unit template contains an @, and upstream maintainer headers are
# supposed to carry addresses -- they are Arch's, publicly published, and a
# PKGBUILD without them would be the anomaly. Six of nine findings were noise,
# which is how a check gets switched off and stops protecting anything.
#
# The author's own address is not covered here either, deliberately: it is in the
# author field of all 89 commits by the project's own convention, so calling it a
# leak in prose while requiring it in metadata would be incoherent. What this
# checks is the machine -- addresses and usernames -- which nothing needs.

# Files that are examples ON PURPOSE. Named one by one, with the reason, because
# a wildcard exclusion is how a real leak gets waved through.
#
# EMPTY, and that is the intended state. .env.example was listed here, exempted
# for carrying a home directory with a literal account name -- then its values
# were made neutral and the exemption had nothing left to excuse. An exemption
# that outlives its reason is how a file stops being checked without anyone
# deciding that it should.
#
# And the first version of this very comment quoted the path it was describing,
# so the check flagged its own source. A redaction tool must not spell out what
# it redacts; there is no reason to name the account to explain why it is gone.
declare -a ALLOW=()

hits=0
for i in "${!PATTERNS[@]}"; do
    while IFS=: read -r file line rest; do
        [ -n "$file" ] || continue
        skip=0
        for a in "${ALLOW[@]}"; do [ "$file" = "$a" ] && skip=1; done
        [ "$skip" -eq 1 ] && continue
        printf '  %-28s %s:%s  %s\n' "${NAMES[$i]}" "$file" "$line" \
            "$(printf '%s' "$rest" | cut -c1-60)"
        hits=$((hits + 1))
    done < <(git grep -nIE "${PATTERNS[$i]}" -- . 2>/dev/null)
done

# Commit messages too. The working tree can be cleaned with an edit; a message
# needs history rewritten, so it is worth knowing early rather than late.
msg=$(git log --all --format='%B' 2>/dev/null |
      grep -cE '\b(192\.168|10|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]{1,3}\.[0-9]{1,3}\b|/home/[a-z]' || true)

if [ "$hits" -eq 0 ] && [ "${msg:-0}" -eq 0 ]; then
    echo "no machine identity, address or username in the tracked files"
    exit 0
fi
[ "${msg:-0}" -gt 0 ] && printf '  %s line(s) in COMMIT MESSAGES -- needs history rewriting\n' "$msg"
printf '%s finding(s)\n' "$((hits + ${msg:-0}))"
exit 1
