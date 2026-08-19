#!/usr/bin/env bash
# python: an unbounded loop that hunts for a free X display number.
#
# build() ends with:
#
#   export servernum=99
#   while ! xvfb-run -a -n "$servernum" /bin/true 2>/dev/null; do
#       servernum=$((servernum+1))
#   done
#   LC_CTYPE=en_US.UTF-8 xvfb-run -s "-screen 0 1920x1080x16 ..." -a \
#       -n "$servernum" make EXTRA_CFLAGS="$CFLAGS"
#
# xvfb-run is not installed here. It fails with 127, `!` inverts that to true,
# servernum increments, and the loop tries again. FOREVER. There is no exit
# condition for "the command does not exist" -- the loop can only end by
# finding a display, and it never will.
#
# THE TRAP IS THE `2>/dev/null`. It swallows the one line that would have
# explained everything. Measured before it was killed: ten hours of wall
# clock, four million PIDs consumed, and a build log frozen at
# `configure: creating Makefile` -- not one byte of output in ten hours. strace
# showed clone/wait4 pairs returning status 127 and no execve at all, because
# bash gives up before exec when a command is not on PATH.
#
# It also defeated every heuristic I had for "is the build progressing":
# the process was alive, burning 40% CPU, with a plausible cwd of
# .../pkg/python/src/Python-3.14.7. A stalled LOG next to a running makepkg is
# the signal that finds this; a process list is not.
#
# WHY REMOVE RATHER THAN INSTALL xvfb. Arch wraps the build in a virtual
# display so that steps which touch tkinter or IDLE have one. A headless
# `make` does not need it -- and stage 2 rebuilds this inside a chroot that
# will have no xvfb either, so installing it on the host would fix one stage
# and leave the other spinning for ten hours. The wrapper goes, in both.
#
# THE SAME LOOP IS IN check(), and that one matters more, not less. Stage 1
# passes --nocheck so it never ran -- but stage 2 drops --nocheck on purpose,
# because that is where a test suite finally means something. It would have
# spun there for ten hours too, on a build nobody was watching. Both copies
# go, and the guard counts them rather than trusting one substitution.
#
# xorg-server-xvfb leaves makedepends with them: it is a package this port
# does not build, so declaring it would be one more entry asking for
# something that will never exist -- the class of gcc-libs/libhwasan.
set -euo pipefail
python3 - <<'PYX'
import io, re
s = io.open("PKGBUILD", encoding="utf-8").read()

# (a) BOTH loops -- build() and check() -- comment line included.
pat = (r"\n *# Obtain next free server number[^\n]*\n"
       r" *export servernum=99\n"
       r" *while ! xvfb-run[^\n]*\n")
n = len(re.findall(pat, s))
assert n == 2, "python: expected 2 xvfb servernum loops, found %d" % n
s = re.sub(pat, "\n", s)

# (b) every xvfb-run wrapper, whatever it wraps.
pat2 = r'xvfb-run (?:-s "[^"]*" )?-a -n "\$servernum" '
m = len(re.findall(pat2, s))
assert m >= 1, "python: no xvfb-run wrapper found"
s = re.sub(pat2, "", s)

# (c) the makedepend on a package this port does not build.
old = "'gdb' 'xorg-server-xvfb' 'ttf-font'"
assert s.count(old) == 1, "python: makedepends not in the expected form"
s = s.replace(old, "'gdb' 'ttf-font'", 1)

assert "xvfb" not in s, "python: an xvfb reference survived"
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
print("python: %d xvfb wrapper(s) and 2 loops removed" % m)
PYX
grep -q 'xvfb' PKGBUILD && { echo "python: xvfb still referenced" >&2; exit 1; }
grep -qF 'LC_CTYPE=en_US.UTF-8 make EXTRA_CFLAGS="$CFLAGS"' PKGBUILD || {
    echo "python: the build make line was not rebuilt correctly" >&2; exit 1; }
grep -q 'servernum' PKGBUILD && {
    echo "python: a servernum reference survived" >&2; exit 1; }
echo "python: xvfb-run wrapper and its unbounded servernum loop removed"
