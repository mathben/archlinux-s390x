#!/usr/bin/env bash
# rsync: no man pages, because nothing here can render them.
#
#   - You need python3 and either the cmarkgfm OR commonmark python3 lib in
#     order to build manpages based on the git source
#   configure.sh: error: Aborting configure run
#
# rsync is built from the git tag, and the git tree ships man pages as Markdown
# rather than nroff -- the release tarballs carry them pre-rendered, the tag
# does not. Rendering wants a Python Markdown library that this port does not
# have at either stage: not on the host, and not in the chroot, where there is
# no pip to reach for.
#
# --disable-md2man is named by the error itself. Same arbitration as
# --auto-features auto in build-stage2.sh: the documentation gives way and the
# tool gets built. Restore at stage 3, alongside the rest of it.
#
# WHY rsync IS HERE AT ALL. It is not part of Arch's base and nothing in this
# port depends on it at runtime. It is a BUILD tool: the kernel's
# headers_install target runs it, so linux-api-headers -- the first entry in
# packages.sh -- cannot be rebuilt inside the chroot without it. The host had
# it from apt, which is precisely why stage 1 never mentioned it.
#
# BOTH STAGES, no skip entry: the chroot has no Markdown renderer either, and
# stage 2 is where rsync is actually needed.
set -euo pipefail
python3 - <<'ZZPY'
import io, re
# LINE-BASED, and [ \t]* rather than \s*.
#
# The first attempt matched r"^(\s*)\./configure" and inserted at the match
# end. It produced
#
#   ./configure \
#                        <- blank line
#       --disable-md2man \
#
# and the guard below caught it. \s MATCHES NEWLINES: with re.M the pattern
# could start at the blank line above, swallow "\n  " into the captured
# indent, and put that newline back into the file. The flag was in the file,
# on its own paragraph, attached to nothing.
#
# Working on the LINE removes the arithmetic entirely -- there is no offset to
# be wrong about.
lines = io.open("PKGBUILD", encoding="utf-8").read().split("\n")
hit = [i for i, l in enumerate(lines) if re.match(r"^[ \t]*\./configure\b", l)]
assert len(hit) == 1, "rsync: expected exactly one ./configure line, got %d" % len(hit)
i = hit[0]
indent = re.match(r"^[ \t]*", lines[i]).group(0)
assert lines[i].rstrip().endswith("\\"), "rsync: ./configure does not continue onto the next line"
lines.insert(i + 1, indent + "    --disable-md2man \\")
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lines))
ZZPY
grep -q -- '--disable-md2man' PKGBUILD || {
    echo "rsync: --disable-md2man was not inserted" >&2; exit 1; }
# The insert must have landed on the configure line, not merely somewhere in the
# file -- a flag in a comment or a later block would look identical to grep.
grep -A1 -E '^\s*\./configure' PKGBUILD | grep -q -- '--disable-md2man' || {
    echo "rsync: the flag is in the file but not on ./configure" >&2; exit 1; }
echo "rsync: man pages disabled (no Markdown renderer at either stage)"
