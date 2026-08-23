#!/usr/bin/env bash
# python-jinja: our flit_core is NEWER than jinja will accept.
#
#   * Getting build dependencies for wheel...
#   ERROR Missing dependencies:
#       flit_core<4
#
# flit_core IS installed, and importable: 4.0.2. jinja's pyproject.toml pins
# `flit_core<4`, so `python -m build` refuses before compiling anything.
#
# A NEW SHAPE for this port, and the mirror image of the one already recorded.
# libxslt could not be built on the host because Ubuntu's libxml2 was too OLD.
# Here our own package is too NEW for another package's declared ceiling. Both
# read as a missing dependency; neither is one.
#
# --skip-dependency-check tells build to compile anyway, and it is not an
# invention: Arch's own python-packaging PKGBUILD passes `-wn
# --skip-dependency-check` for the same class of reason. The pin is upstream
# caution -- flit_core 4 changed no API jinja uses, and jinja builds and imports
# fine against it.
#
# The honest alternative was pinning flit-core to 3.x for the whole
# distribution, which would trade one package's ceiling for every other
# package's floor.
set -euo pipefail
python3 - <<'ZZPY'
import io, re
lines = io.open("PKGBUILD", encoding="utf-8").read().split("\n")
hit = [i for i, l in enumerate(lines) if re.search(r"python -m build\b", l)]
assert len(hit) == 1, "python-jinja: expected one `python -m build`, got %d" % len(hit)
i = hit[0]
assert "--skip-dependency-check" not in lines[i], "python-jinja: already skipping"
lines[i] = lines[i].rstrip() + " --skip-dependency-check"
io.open("PKGBUILD", "w", encoding="utf-8").write("\n".join(lines))
ZZPY
grep -q -- "python -m build .*--skip-dependency-check" PKGBUILD || {
    echo "python-jinja: the flag is not on the build line" >&2; exit 1; }
echo "python-jinja: dependency check skipped (our flit_core is 4.x, the pin says <4)"
