#!/usr/bin/env bash
# readline: its .pc file requires a module nothing in the repository provides.
#
#   Package 'termcap', required by 'readline', not found
#
# readline's configure writes `Requires.private: termcap` into readline.pc,
# because that is the historical name of the terminal library it links. Our
# ncurses package ships tinfo.pc and ncurses.pc -- there is no termcap.pc, and
# nothing else in the repository supplies one.
#
# Nothing fails at build time. The .pc is data, and pkg-config only follows
# Requires.private when a CONSUMER asks. The first consumer to ask was libxml2,
# inside the stage-2 chroot, and it stopped at meson configure -- three
# packages and one stage away from the cause.
#
# tinfo is the right name: it is what ncurses actually installs the terminfo
# routines into (`--with-termlib`), and readline links -lncurses which pulls it.
# This is the same substitution the host needed for history.pc, made for the
# same reason, in the other direction: there the file was missing and had to be
# generated, here it exists and names the wrong dependency.
#
# The package's .pc is patched in package(), after make install writes it, so
# nothing in the build sees a different file than what ships.
set -euo pipefail
python3 - <<'ZZPY'
import io, re
s = io.open("PKGBUILD", encoding="utf-8").read()
# AFTER make install, not at the top of package(). The first version anchored
# on `package() {` and ran the sed before the file existed:
#   sed: can't read .../usr/lib/pkgconfig/readline.pc: No such file or directory
m = re.search(r'^  make -C \$pkgname-\$_basever DESTDIR="\$pkgdir" install\n', s, re.M)
assert m, "readline: the install line in package() is not in the expected form"
fix = """  # readline.pc says `Requires.private: termcap`; this repository ships
  # tinfo.pc, not termcap.pc, so any consumer asking pkg-config about readline
  # fails on a module nobody provides.
  sed -i 's/^Requires.private: termcap$/Requires.private: tinfo/' \\
      "$pkgdir"/usr/lib/pkgconfig/readline.pc
  grep -q '^Requires.private: tinfo$' "$pkgdir"/usr/lib/pkgconfig/readline.pc
"""
s = s[:m.end()] + fix + s[m.end():]
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
ZZPY
grep -q 'Requires.private: tinfo' PKGBUILD || {
    echo "readline: the .pc substitution was not inserted" >&2; exit 1; }
echo "readline: readline.pc now requires tinfo (termcap.pc does not exist here)"
