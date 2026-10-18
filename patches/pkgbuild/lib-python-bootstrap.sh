#!/usr/bin/env bash
# Arch's own escape hatch for the Python packaging cycle. Sourced by the six
# hooks that need it; not a hook itself.
#
# THE CYCLE. Three stage-2 builds -- brotli, libseccomp, meson -- stopped on
#
#   /usr/bin/python: No module named build
#
# and building python-build means running `python -m build`, which is
# python-build. Its dependencies are the same: packaging and pyproject-hooks are
# flit_core-backed, installing a wheel wants python-installer, and none of them
# exist yet.
#
# On the host the cycle was already broken -- apt had python3-build -- so stage 1
# never met it. Trying to break it there again failed for a reason worth
# recording: `apt-cache policy python3-flit-core` returns no candidate at all.
# Ubuntu does not package it, so the backend every one of these needs cannot be
# installed on the host by any means. Our own python-flit-core builds fine, but
# building a package is not installing it.
#
# ARCH ALREADY SOLVED THIS, and the solution is in the PKGBUILDs:
#
#   if (( _bootstrap == 0 )); then
#     python -m build -wn --skip-dependency-check
#   else
#     cd python-bootstrap
#     python -m bootstrap.build
#   fi
#
# python-bootstrap is a vendored builder that needs none of the six. Setting
# _bootstrap=1 is upstream's supported path through exactly this situation --
# far better than the alternative that was half-written here first, which was a
# per-package hook calling `python -m flit_core.wheel` and unzipping the result
# into $pkgdir by hand. That would have been three bespoke reimplementations of
# something the PKGBUILD already does properly.
#
# It also means these build on the HOST, where they had failed, so they need no
# stage-2 special handling at all.
set -euo pipefail
# A PROBE, not a constant, and it runs in the BUILD ENVIRONMENT.
#
# The first version set _bootstrap=1 unconditionally. That is right on a machine
# with no Python packaging stack and wrong the moment there is one, because the
# vendored builder carries its OWN copy of each project -- older than the
# PKGBUILD's pkgver. python-packaging was labelled 26.3 and installed 25.0, and
# the mismatch surfaced two packages later:
#
#   python-vcs-versioning: packaging>=26.2
#
# a floor our own package met on paper and not in fact. Nothing about the
# installed package looked wrong; only `import packaging; packaging.__version__`
# disagreed with its name.
#
# So the PKGBUILD decides at build time, where the answer is knowable: if `build`
# and `installer` import, the real path works and the vendored copies are not
# wanted. Hooks run on the HOST even for stage 2, so a probe written here could
# not answer for the chroot -- this one is evaluated by makepkg, inside it.
python3 - <<'ZZPY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()
old = "_bootstrap=0"
assert s.count(old) == 1, "python bootstrap: expected one _bootstrap=0, got %d" % s.count(old)
new = ("# Bootstrap only when the real path is unavailable -- see\n"
       "# patches/pkgbuild/lib-python-bootstrap.sh. Evaluated by makepkg, in the\n"
       "# build environment, because that is where the answer lives.\n"
       "_bootstrap=1\n"
       "python -c 'import build, installer' >/dev/null 2>&1 && _bootstrap=0")
s = s.replace(old, new, 1)
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
ZZPY
grep -q "^_bootstrap=1$" PKGBUILD || {
    echo "python bootstrap: the default was not set to 1" >&2; exit 1; }
grep -q "import build, installer" PKGBUILD || {
    echo "python bootstrap: the probe was not inserted" >&2; exit 1; }
# The branch it selects must actually exist, or the switch silently builds
# nothing -- these PKGBUILDs are not required to have both halves.
grep -q "bootstrap.build" PKGBUILD || {
    echo "python bootstrap: no bootstrap.build branch in this PKGBUILD" >&2; exit 1; }

# UNE SOMME PAR SOURCE, SUR LA BRANCHE DU BATISSEUR.
#
# source= est conditionnel dans ces recettes : deux entrees sur le chemin
# normal, huit sur celui du batisseur embarque. Les tableaux de sommes, eux,
# ne le sont pas et decrivent le chemin normal. makepkg compare les TAILLES
# avant toute empreinte :
#
#   ==> ERROR: Integrity checks (b2) differ in size from the source array.
#
# Invisible a l'etage 1, ou la sonde donne 0 et ou les deux tableaux
# s'accordent ; fatal dans le chroot, ou elle donne 1. C'est la raison d'etre
# de ce fichier partage : la faute est commune aux six, le correctif aussi.
#
# Les huit sources sont des depots git, et makepkg n'attend que SKIP d'une
# source VCS -- son contenu est fixe par l'etiquette ou le commit, pas par une
# empreinte d'archive. Chaque tableau PRESENT est refait depuis source=, pour
# qu'une recette qui change d'algorithme ou une source ajoutee en amont
# n'ouvrent pas le meme trou.
python3 - <<'ZZSUMS'
import io, re
s = io.open("PKGBUILD", encoding="utf-8").read()
m = re.search(r'^[a-z_][a-z0-9_]*\(\)\s*\{', s, re.M)
assert m, "python bootstrap: aucune fonction ou ancrer le recalcul des sommes"
add = (
    "# Une somme SKIP par source sur la branche du batisseur : voir\n"
    "# patches/pkgbuild/lib-python-bootstrap.sh.\n"
    "if (( _bootstrap != 0 )); then\n"
    "  for _a in md5sums sha1sums sha224sums sha256sums sha384sums \\\n"
    "            sha512sums b2sums; do\n"
    "    declare -p \"$_a\" >/dev/null 2>&1 || continue\n"
    "    eval \"$_a=( \\$(printf 'SKIP %.0s' \\\"\\${source[@]}\\\") )\"\n"
    "  done\n"
    "  unset _a\n"
    "fi\n\n"
)
s = s[:m.start()] + add + s[m.start():]
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
ZZSUMS
grep -q "SKIP %.0s" PKGBUILD || {
    echo "python bootstrap: le recalcul des sommes n a pas ete pose" >&2; exit 1; }
# Le controle qui compte, et il doit valoir sur la branche REELLEMENT prise.
bash -c 'CARCH=s390x; source ./PKGBUILD >/dev/null 2>&1
  for _a in md5sums sha1sums sha224sums sha256sums sha384sums sha512sums b2sums; do
      declare -p "$_a" >/dev/null 2>&1 || continue
      eval "n=\${#$_a[@]}"
      [ "$n" -eq "${#source[@]}" ] || {
          echo "python bootstrap: ${#source[@]} sources pour $n $_a" >&2; exit 1; }
  done' || exit 1
echo "$(basename "$PWD"): _bootstrap=1 (Arch's vendored builder), sommes recalculees"
