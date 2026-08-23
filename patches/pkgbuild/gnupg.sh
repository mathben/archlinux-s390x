#!/usr/bin/env bash
# gnupg: no manual, because two diagrams in it need two image toolchains.
#
#   /bin/sh: line 1: convert: command not found
#   make[2]: *** [Makefile:1199: gnupg-module-overview.pdf] Error 127
#   /bin/sh: line 1: fig2dev: command not found
#   make[2]: *** [Makefile:1211: gnupg-card-architecture.pdf] Error 127
#
# `convert` is ImageMagick, `fig2dev` is transfig. Two separate toolchains, for
# two architecture diagrams in gnupg's own documentation.
#
# --disable-doc is gnupg's own switch, and it was CHECKED before being used:
# `grep -oE '\-\-(disable|enable)-doc' configure` finds both, so autoconf knows
# the option. groff had no such switch and needed its generated Makefile edited
# instead -- the difference matters, because an invented flag draws only a
# warning from autoconf and the build fails exactly as before, with the hook's
# own check passing.
set -euo pipefail
# AN ARRAY, not a continued command. The first version of this hook looked for a
# ./configure line ending in a backslash and asserted its way out:
#
#   AssertionError: gnupg: ./configure does not continue
#
# gnupg collects its options in `local configure_options=( ... )` and then calls
# `./configure "${configure_options[@]}"`. Both shapes appear in this port --
# binutils, cryptsetup and libxcrypt use continued commands; gnupg and shadow use
# arrays -- so a hook has to look at the file rather than assume the house style.
python3 - <<'ZZPY'
import io, re
lines = io.open("PKGBUILD", encoding="utf-8").read().split("\n")
hit = [i for i, l in enumerate(lines) if re.match(r"^[ \t]*local configure_options=\($", l)]
assert len(hit) == 1, "gnupg: expected one configure_options array, got %d" % len(hit)
i = hit[0] + 1
ind = re.match(r"^[ \t]*", lines[i]).group(0)
# The array is kept in alphabetical order upstream; --disable-doc sorts first.
lines.insert(i, ind + "--disable-doc  # no ImageMagick, no transfig for the diagrams")
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lines))
ZZPY
grep -A2 "local configure_options=(" PKGBUILD | grep -q -- "--disable-doc" || {
    echo "gnupg: the flag is not inside the options array" >&2; exit 1; }
echo "gnupg: manual disabled (no ImageMagick, no transfig)"
