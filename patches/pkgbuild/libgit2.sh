#!/usr/bin/env bash
# libgit2: its own bundled HTTP parser, so that nodejs stays out of this port.
#
# depends=(llhttp), and Arch llhttp package is built by running npm install and
# ts-node over the nodejs/llhttp tree -- the parser is GENERATED from TypeScript.
# Pulling that in would mean nodejs and npm, a language runtime and a package
# manager, so that libgit2 can parse HTTP responses.
#
# libgit2 ships the same parser in deps/llhttp and its cmake takes
# USE_HTTP_PARSER=builtin for exactly this case. Same code, no toolchain.
#
# The depends entry goes with the flag: leaving it would name a package this
# port does not build, and the RESOLVE check would be right to complain.
set -euo pipefail
python3 - <<"ZZPY"
import io
s = io.open("PKGBUILD", encoding="utf-8").read()

old = "-D USE_HTTP_PARSER=llhttp"
assert s.count(old) == 1, "libgit2: expected one USE_HTTP_PARSER, got %d" % s.count(old)
s = s.replace(old, "-D USE_HTTP_PARSER=builtin", 1)

lines = s.split("\n")
dep0 = lines.index("depends=(")
dep1 = next(i for i in range(dep0, len(lines)) if lines[i] == ")")
hit = [i for i in range(dep0, dep1) if lines[i].strip() == "llhttp"]
assert len(hit) == 1, "libgit2: llhttp not found once in depends"
del lines[hit[0]]
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lines))
ZZPY
grep -q -- "-D USE_HTTP_PARSER=builtin" PKGBUILD || { echo "libgit2: still asking for llhttp" >&2; exit 1; }
sed -n "/^depends=(/,/^)/p" PKGBUILD | grep -q llhttp && { echo "libgit2: llhttp still a dependency" >&2; exit 1; }
echo "libgit2: bundled HTTP parser, llhttp dependency dropped"
