#!/usr/bin/env bash
# The upstream commit of every package checkout, recorded and enforced.
#
# WHY THIS EXISTS. Every PKGBUILD in this port comes from a fresh
# `git clone --depth 1` of gitlab.archlinux.org, and the 63 hooks under
# patches/pkgbuild/ assert EXACT strings:
#
#   assert s.count(old) == 1, "binutils: expected one --enable-pgo-build ..."
#
# That strictness is deliberate and it works -- several hooks have caught their
# own mistakes that way. But it means the port is written against a moving
# target. The day Arch bumps a version, a hook fails; and someone starting over
# today does not get what this port was written against, they get whatever Arch
# has today.
#
# So before this file, the honest description was: the port worked once, on one
# machine. What was missing to change that is not the 18 GB of build output --
# all of it regenerable -- but the one number per checkout that says which
# upstream commit it was.
#
#   write     record the current HEAD of every checkout under $WORK/pkg
#   verify    report checkouts that have moved away from the lock (default)
#   restore   put every checkout back on its locked commit
#
# NOT versioned alongside this: repo/s390x and repo2/s390x (800 MB of binaries a
# script can rebuild), rootfs-stage2 (wiped every run by design), stage1.state
# and stage2.state (derived from what is really in repo/s390x -- versioning them
# would invite them to disagree with it), and the build logs.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="${WORK:-$HOME/work/arch-s390x}"
LOCK="${LOCK:-$HERE/upstream.lock}"

usage() { printf 'usage: %s [write|verify|restore]\n' "${0##*/}" >&2; exit 2; }

# The remote is READ from each checkout, not rebuilt from a base URL. Most come
# from archlinux/packaging/packages, pacman does not, and guessing would put a
# wrong URL in a file whose whole purpose is to be trusted later.
_scan() {
    local d name sha url
    for d in "$WORK"/pkg/*/; do
        [ -d "$d/.git" ] || continue
        name=$(basename "$d")
        sha=$(git -C "$d" rev-parse HEAD 2>/dev/null) || continue
        url=$(git -C "$d" remote get-url origin 2>/dev/null) || continue
        printf '%s %s %s\n' "$name" "$sha" "$url"
    done | sort
}

cmd_write() {
    local tmp
    tmp=$(mktemp)
    {
        printf '# Upstream commit of every package checkout in this port.\n'
        printf '# Regenerate with: bash scripts/upstream-lock.sh write\n'
        printf '# Verify with:     bash scripts/upstream-lock.sh verify\n'
        printf '#\n'
        printf '# <package> <commit> <url>\n'
        _scan
    } > "$tmp"
    mv "$tmp" "$LOCK"
    printf 'wrote %s entries to %s\n' "$(grep -vc '^#' "$LOCK")" "$LOCK"
}

cmd_verify() {
    [ -f "$LOCK" ] || { echo "no lock file at $LOCK" >&2; return 2; }
    local n=0 moved=0 missing=0 name sha url cur
    while read -r name sha url; do
        case "$name" in ''|'#'*) continue ;; esac
        n=$((n + 1))
        if [ ! -d "$WORK/pkg/$name/.git" ]; then
            printf '  ABSENT  %s\n' "$name"; missing=$((missing + 1)); continue
        fi
        cur=$(git -C "$WORK/pkg/$name" rev-parse HEAD 2>/dev/null)
        if [ "$cur" != "$sha" ]; then
            printf '  MOVED   %-24s %s -> %s\n' "$name" "${sha:0:9}" "${cur:0:9}"
            moved=$((moved + 1))
        fi
    done < "$LOCK"
    # THE OTHER DIRECTION, which is the one that goes wrong silently. Above
    # answers "has a locked checkout moved?"; this answers "is the lock still
    # covering the port?" A package added to packages.sh and never locked builds
    # against whatever upstream has that day, and nothing about the lock file
    # looks wrong -- it is complete for everything it mentions.
    local unlocked=0 p
    if [ -f "$HERE/packages.sh" ]; then
        # shellcheck disable=SC1090
        HERE="$HERE" source "$HERE/packages.sh"
        for p in "${STAGE1_PACKAGES[@]}"; do
            grep -q "^$p " "$LOCK" || { printf '  UNLOCKED %s\n' "$p"; unlocked=$((unlocked + 1)); }
        done
    fi
    printf '%s locked, %s moved, %s absent, %s unlocked\n' \
        "$n" "$moved" "$missing" "$unlocked"
    # A checkout that is absent is not a failure: it has simply not been cloned
    # on this machine yet. One that MOVED is, because a hook was written against
    # the other commit. UNLOCKED is reported but not fatal -- a package added to
    # the list and not yet built has nothing to lock, and `write` covers it once
    # it does.
    [ "$moved" -eq 0 ]
}

cmd_restore() {
    [ -f "$LOCK" ] || { echo "no lock file at $LOCK" >&2; return 2; }
    local ok=0 fail=0 name sha url
    while read -r name sha url; do
        case "$name" in ''|'#'*) continue ;; esac
        local d="$WORK/pkg/$name"
        if [ ! -d "$d/.git" ]; then
            mkdir -p "$d"
            git -C "$d" init -q 2>/dev/null
            git -C "$d" remote add origin "$url" 2>/dev/null
        fi
        # --depth 1 of a specific commit, because that is how these were cloned
        # and a full history of 155 repositories is not wanted. It needs
        # uploadpack.allowReachableSHA1InWant on the server; when that is
        # refused the failure is reported rather than skipped, since a checkout
        # left on the wrong commit is exactly what this file exists to prevent.
        if git -C "$d" fetch -q --depth 1 origin "$sha" 2>/dev/null &&
           git -C "$d" checkout -q --detach FETCH_HEAD 2>/dev/null; then
            ok=$((ok + 1))
        else
            printf '  FAILED  %-24s %s\n' "$name" "${sha:0:9}"
            fail=$((fail + 1))
        fi
    done < "$LOCK"
    printf '%s restored, %s failed\n' "$ok" "$fail"
    [ "$fail" -eq 0 ]
}

case "${1:-verify}" in
    write)   cmd_write ;;
    verify)  cmd_verify ;;
    restore) cmd_restore ;;
    *)       usage ;;
esac
