#!/usr/bin/env bash
# pinentry: three graphical front ends, on a machine with no display stack.
#
#   configure: error:
#       ***
#       *** Qt6 (Qt6Core, Qt6Gui, Qt6Widgets) is required.
#       ***
#
# Arch builds every front end pinentry has -- tty, curses, emacs, gnome3 and
# qt -- and declares qt6-base, gcr, kguiaddons and kwindowsystem as
# makedepends. None of that exists on this build host, and none of it belongs
# in a bootstrap: pacman needs a passphrase prompt on a terminal, nothing more.
#
# THE HONEST FRAMING. This is not architectural -- Qt runs on s390x perfectly
# well. It is deferred, and TODO.md says so: a desktop on Z would want these
# back, and the way back is to build qt6-base and the KDE pieces first. What
# is not defensible is dragging a GUI toolkit into the closure of a package
# manager's passphrase prompt.
#
# THE SECOND PLACE, and then a THIRD. libsecret and glib2 are in the top-level
# depends= and exist only to serve the front ends being switched off. --nodeps
# means makepkg never checks them, so leaving them would ship a pinentry that
# cannot install -- the same trap as gcc-libs/libhwasan, make/guile and
# gnutls/leancrypto.
#
# The third place is package(), which APPENDS more:
#
#   depends+=( libglib-2.0.so libncursesw.so libsecret-1.so )
#
# The first version of this hook fixed the array at the top of the file, ran
# its guard against that array, passed, and shipped the append untouched. The
# guard checked the place I was thinking about rather than every place the
# name occurs -- which is exactly the mistake the note above warns against.
# Only libncursesw.so survives; the other two name libraries this build no
# longer links.
#
# tty, curses and fallback-curses stay, and so does emacs: it is a protocol
# over a pipe, not a toolkit, and it links nothing extra.
set -euo pipefail
python3 - <<'PY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()

for flag in ("--enable-pinentry-gnome3", "--enable-pinentry-qt", "--enable-libsecret"):
    off = flag.replace("--enable-", "--disable-", 1)
    assert s.count(flag) == 1, "pinentry: expected exactly one %s" % flag
    s = s.replace(flag, off, 1)

old = "  'glibc' 'ncurses' 'libassuan' 'libsecret' 'glib2'\n"
assert s.count(old) == 1, "pinentry: depends block not in the expected form"
s = s.replace(old, "  'glibc' 'ncurses' 'libassuan'\n", 1)

# package() appends three sonames; two of them are gone with the front ends.
old = "  depends+=(\n    libglib-2.0.so\n    libncursesw.so\n    libsecret-1.so\n  )\n"
assert s.count(old) == 1, "pinentry: package() depends+= not in the expected form"
s = s.replace(old, "  depends+=(\n    libncursesw.so\n  )\n", 1)

# package() renames the GTK binary, which is no longer built.
old = '  # The -gtk backend has been built to be used with GTK3.\n  mv "${pkgdir}/usr/bin/pinentry-gtk"{-2,}\n'
assert s.count(old) == 1, "pinentry: gtk rename not in the expected form"
s = s.replace(old, "", 1)

io.open("PKGBUILD", "w", encoding="utf-8").write(s)
PY
for f in gnome3 qt libsecret; do
    grep -q -- "--disable-pinentry-$f\|--disable-$f" PKGBUILD || {
        echo "pinentry: $f front end still enabled" >&2; exit 1; }
done
grep -qE "^  'glibc' 'ncurses' 'libassuan'$" PKGBUILD || {
    echo "pinentry: depends not reduced" >&2; exit 1; }
# EVERY place the names occur -- but as they are actually WRITTEN, not as bare
# substrings. The first version of this loop grepped for `libsecret` and
# matched the `--disable-libsecret` it had just inserted, so a correct patch
# reported failure. Third guard in this port to check something adjacent to
# what it meant; the lesson is that a guard needs the same care as the edit.
for n in "'libsecret'" "'glib2'" "libglib-2.0.so" "libsecret-1.so" \
         "--enable-libsecret" "--enable-pinentry-qt" "--enable-pinentry-gnome3" \
         'pinentry-gtk"{-2,}'; do
    grep -qF -- "$n" PKGBUILD && {
        echo "pinentry: $n still present" >&2; exit 1; }
done
grep -q -- "--enable-pinentry-curses" PKGBUILD || {
    echo "pinentry: curses front end lost -- nothing would prompt" >&2; exit 1; }
echo "pinentry: tty/curses/emacs only (no Qt, GNOME or libsecret on this host)"
