#!/usr/bin/env bash
# Prove the repository, by installing it and running it.
#
# WHY THIS IS A SCRIPT AND NOT A PROCEDURE
#
# Sixty-eight successful builds said nothing that turned out to be true about
# whether the port worked. One chroot did -- it found the missing dynamic
# linker and the missing packages in a single run. That test was then done by
# hand, so it was not repeatable, and the next question ("is it still true?")
# had no cheap answer.
#
# It has one now. Three things are checked, and they fail for different
# reasons, so they are reported separately rather than as one verdict:
#
#   1. RESOLVE   -- pacman's own dependency resolver, with --nodeps OFF. This
#                   is the check the bootstrap deliberately skips all the way
#                   through stage 1, so it is the first time anything asks
#                   whether the repository is internally complete.
#   2. ARTEFACT  -- static audit of every package for host contamination that
#                   does not raise an error: Debian multiarch libdirs, files
#                   under /usr/local, binaries linked to libselinux.
#   3. RUN       -- chroot in and execute the binaries. The only check that
#                   can catch a missing ld.so, because a package whose
#                   interpreter is absent installs perfectly.
#
# Read-only with respect to repo/s390x. Wipes and rebuilds its own rootfs.
set -uo pipefail

WORK="${WORK:-$HOME/work/arch-s390x}"
REPO="${REPO:-$WORK/repo/s390x}"
ROOT="${ROOT:-$WORK/rootfs-test}"
CONF="$WORK/pacman-test.conf"

# The set a rootfs needs to reach a shell prompt and manage itself. filesystem
# is not optional and not obvious: its usr-merge symlinks are what create
# /lib/ld64.so.1, and without that path nothing starts at all -- the error is
# "chroot: No such file or directory" on a binary that is plainly there.
PKGS=(filesystem glibc bash coreutils tar sed grep findutils gawk pacman)

fail=0
note() { printf '\n== %s ==\n' "$*"; }
bad()  { printf '  FAIL  %s\n' "$*"; fail=$((fail + 1)); }
good() { printf '  ok    %s\n' "$*"; }

note "Repository index"
[ -f "$REPO/core.db.tar.gz" ] || { bad "no core.db in $REPO"; exit 1; }
printf '  %s packages\n' "$(ls "$REPO"/*.pkg.tar.* 2>/dev/null | wc -l)"

cat > "$CONF" <<EOF
[options]
Architecture = s390x
SigLevel = Never
[core]
Server = file://$REPO
EOF

note "1. RESOLVE -- pacman's own dependency check, --nodeps OFF"
# -p prints what it would do and installs nothing. If the repository is
# incomplete, pacman names the missing package here, precisely, for free.
#
# The root and its dbpath must EXIST before alpm will initialise -- pacman
# reports that as "failed to resolve path ... passed to --root", which reads
# like a bad argument rather than a directory it declined to create.
sudo rm -rf "$ROOT.probe"; sudo mkdir -p "$ROOT.probe/var/lib/pacman"
# -Syp, not -Sp. A fresh dbpath has no sync database, and without -y pacman
# reports every package as "target not found" -- which reads like an empty
# repository rather than an unread index.
if sudo pacman --root "$ROOT.probe" --config "$CONF" \
        --noconfirm -Syp "${PKGS[@]}" > "$WORK/resolve.txt" 2>&1; then
    good "resolver satisfied ($(grep -c '^file://' "$WORK/resolve.txt") packages)"
else
    bad "unresolved dependencies:"
    grep -E "unable to satisfy|target not found" "$WORK/resolve.txt" \
        | sed 's/.*dependency //; s/ required by.*//' | sort -u | tr '\n' ' ' \
        | fold -sw 68 | sed 's/^/        /'
fi
sudo rm -rf "$ROOT.probe"

note "2. ARTEFACT -- host contamination that raises no error"
n=0
for f in "$REPO"/*.pkg.tar.*; do
    c=$(bsdtar -tf "$f" 2>/dev/null | grep -c 's390x-linux-gnu/')
    [ "$c" -gt 0 ] && { bad "$(basename "$f"): $c multiarch paths"; n=$((n + 1)); }
done
[ "$n" -eq 0 ] && good "no Debian multiarch libdir anywhere"

note "3. RUN -- install for real, then chroot"
sudo rm -rf "$ROOT"; sudo mkdir -p "$ROOT/var/lib/pacman"
if ! sudo pacman --root "$ROOT" --config "$CONF" --noconfirm -Sy "${PKGS[@]}" \
        > "$WORK/install.txt" 2>&1; then
    bad "install failed, see $WORK/install.txt"
    tail -15 "$WORK/install.txt" | sed 's/^/        /'
    exit 1
fi
good "installed $(sudo ls "$ROOT/var/lib/pacman/local" | wc -l) packages"

# Each command answers a different question, so each is reported on its own.
# `tar` and `find` are here because stage 2 runs makepkg inside this rootfs
# and makepkg calls both -- a failure here stops stage 2 before its first
# package, and would otherwise be discovered much further from its cause.
while read -r desc cmd; do
    out=$(sudo chroot "$ROOT" /usr/bin/env -i PATH=/usr/bin sh -c "$cmd" 2>&1)
    rc=$?
    if [ "$rc" -eq 0 ]; then good "$desc: ${out%%$'\n'*}"
    else bad "$desc: rc=$rc ${out%%$'\n'*}"; fi
done <<'CHECKS'
bash bash --version
arch uname -m
libc ldd --version
ls ls /usr/bin >/dev/null && echo listed
tar tar --version
find find /usr/bin -maxdepth 1 -name sh >/dev/null && echo searched
sed echo x | sed s/x/y/
pacman pacman --version
CHECKS

note "Verdict"
if [ "$fail" -eq 0 ]; then
    echo "  the repository resolves, is clean, and runs."
else
    echo "  $fail check(s) failed -- see above."
fi
exit "$fail"
