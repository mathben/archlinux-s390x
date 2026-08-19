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
#   3. SONAME    -- every library any shipped binary ASKS for, minus every
#                   library the repository SHIPS. This is the check that reads
#                   binaries instead of declarations, and it is the only one
#                   that can see an under-declared dependency: kbd's loadkeys
#                   needed libxkbcommon.so.0 while kbd declared glibc, gzip
#                   and pam. RESOLVE was satisfied, the rootfs installed, and
#                   loadkeys could not start.
#   4. RUN       -- chroot in and execute the binaries. The only check that
#                   can catch a missing ld.so, because a package whose
#                   interpreter is absent installs perfectly.
#
# Read-only with respect to repo/s390x. Wipes and rebuilds its own rootfs.
set -uo pipefail

WORK="${WORK:-$HOME/work/arch-s390x}"
REPO="${REPO:-$WORK/repo/s390x}"
ROOT="${ROOT:-$WORK/rootfs-test}"
CONF="$WORK/pacman-test.conf"
# A cache of its own, wiped every run.
#
# pacman's default cache is /var/cache/pacman/pkg, which is HOST-WIDE and
# survives between runs. A package rebuilt at the same pkgver-pkgrel -- which
# every fix in this port does -- leaves the old file there while core.db
# records the new checksum, and the next install stops on
#
#   File .../coreutils-9.11-2-s390x.pkg.tar.gz is corrupted
#   (invalid or corrupted package (checksum))
#
# which reads like a damaged build rather than a stale copy. The shared cache
# is also not this test's to empty: other work on this host uses it.
CACHE="$WORK/pacman-test.cache"

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
sudo rm -rf "$ROOT.probe" "$CACHE"; sudo mkdir -p "$ROOT.probe/var/lib/pacman" "$CACHE"
# -Syp, not -Sp. A fresh dbpath has no sync database, and without -y pacman
# reports every package as "target not found" -- which reads like an empty
# repository rather than an unread index.
if sudo pacman --root "$ROOT.probe" --config "$CONF" --cachedir "$CACHE" \
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

note "3. SONAME -- what binaries ask for versus what the repository ships"
# Two passes over the packages: collect the soname each shared library
# DECLARES, and every soname each binary REQUESTS. The difference is a set of
# libraries that will be missing at runtime on the target.
#
# Most entries here are the ordinary stage-1 artefact -- the host's soname
# version rather than Arch's, e.g. libgpgme.so.11 where our gpgme package
# ships .45 -- and stage 2 resolves those by rebuilding inside the chroot.
# What must not be ignored is the other kind: a library no package in the
# repository provides at any version.
_sa=$(mktemp -d)
: > "$_sa/have"; : > "$_sa/want"
for f in "$REPO"/*.pkg.tar.*; do
    rm -rf "$_sa/x"; mkdir -p "$_sa/x"
    bsdtar -xf "$f" -C "$_sa/x" usr 2>/dev/null || continue
    _pn=$(bsdtar -xOf "$f" .PKGINFO 2>/dev/null | sed -n 's/^pkgname = //p')
    while IFS= read -r b; do
        readelf -d "$b" 2>/dev/null | sed -n 's/.*Library soname: \[\(.*\)\].*/\1/p' >> "$_sa/have"
        readelf -d "$b" 2>/dev/null | sed -n 's/.*Shared library: \[\(.*\)\].*/\1/p' \
            | sed "s|^|$_pn |" >> "$_sa/want"
    done < <(find "$_sa/x" -type f 2>/dev/null)
done
sort -u "$_sa/have" > "$_sa/have.s"
awk '{print $2}' "$_sa/want" | sort -u > "$_sa/want.s"
if [ -s "$(comm -13 "$_sa/have.s" "$_sa/want.s" > "$_sa/miss"; echo "$_sa/miss")" ]; then
    bad "$(wc -l < "$_sa/miss") soname(s) requested and never shipped:"
    while read -r m; do
        printf '        %-24s <- %s\n' "$m" \
            "$(awk -v m="$m" '$2==m {print $1}' "$_sa/want" | sort -u | tr '\n' ' ')"
    done < "$_sa/miss"
else
    good "every requested soname is shipped by some package"
fi
rm -rf "$_sa"

note "4. RUN -- install for real, then chroot"
sudo rm -rf "$ROOT" "$CACHE"; sudo mkdir -p "$ROOT/var/lib/pacman" "$CACHE"
if ! sudo pacman --root "$ROOT" --config "$CONF" --cachedir "$CACHE" \
        --noconfirm -Sy "${PKGS[@]}" \
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
