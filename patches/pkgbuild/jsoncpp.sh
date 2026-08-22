#!/usr/bin/env bash
# jsoncpp: no doxygen build.
#
#   File "doxybuild.py", line 82, in assert_is_exe
#     raise Exception('path is empty.')
#
# A python traceback, which is what makes this one hard to read: doxybuild.py was
# handed an empty doxygen path because there is no doxygen, and it reports that
# as a path problem. build() runs it after the compile has already finished.
set -euo pipefail
python3 - <<'ZZPY'
import io, re
lines = io.open("PKGBUILD", encoding="utf-8").read().split("\n")
# The call spans several lines: find it and drop through its last continuation.
hit = [i for i, l in enumerate(lines) if re.search(r"python doxybuild\.py", l)]
assert len(hit) == 1, "jsoncpp: expected one doxybuild call, got %d" % len(hit)
i = hit[0]
j = i
while lines[j].rstrip().endswith("\\"):
    j += 1
del lines[i:j + 1]
# The `echo "Building docs..."` above it would now announce nothing.
if i > 0 and "Building docs" in lines[i - 1]:
    del lines[i - 1]
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lines))
ZZPY
grep -q "doxybuild" PKGBUILD && { echo "jsoncpp: doxybuild survived" >&2; exit 1; }
echo "jsoncpp: doxygen build removed"
