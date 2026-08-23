#!/usr/bin/env bash
# autoconf-archive: take the patch from a mirror savannah's cgit will serve.
#
#   curl: (52) Empty reply from server
#   ==> ERROR: Failure while downloading
#       https://cgit.git.savannah.gnu.org/cgit/autoconf-archive.git/patch/?id=241f7ae...
#
# The tarball comes from ftpmirror.gnu.org and arrives fine. What fails is a
# single patch fetched from savannah's cgit /patch/?id= endpoint, which returns
# nothing at all -- measured, not assumed:
#
#   savannah /patch/?id=       (no response)
#   github   /commit/.patch    200, 2463 bytes
#
# savannah itself is up (its root answers 302); it is that endpoint, which cgit
# generates on demand and rate-limits.
#
# The mirror is asked for THE SAME COMMIT, by its full hash, so this changes
# where the bytes come from and not which bytes they are -- the substantive
# difference from replacing a source with a different version of itself. GitHub
# renders `git format-patch` output where cgit renders its own; both are what
# `patch` expects, and the build fails loudly if that were untrue.
#
# WHY NOT DROP THE PATCH. It is 0001_fix_AX_CXX_COMPILE_STDCXX.patch, a fix to a
# macro this port needs -- tpm2-tss stopped on a missing AX_* macro, which is why
# autoconf-archive is in the list at all.
set -euo pipefail
python3 - <<'ZZPY'
import io, re
s = io.open("PKGBUILD", encoding="utf-8").read()
old = "https://cgit.git.savannah.gnu.org/cgit/autoconf-archive.git/patch/?id="
assert s.count(old) == 1, "autoconf-archive: expected one cgit patch URL, got %d" % s.count(old)
# The commit hash follows the URL, up to the closing quote. Reused verbatim: the
# point of the substitution is that the content is identical.
m = re.search(re.escape(old) + r"([0-9a-f]{40})", s)
assert m, "autoconf-archive: no 40-character commit hash after the cgit URL"
sha = m.group(1)
s = s.replace(old + sha,
              "https://github.com/autoconf-archive/autoconf-archive/commit/%s.patch" % sha, 1)
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
print("  patch commit: %s" % sha[:12])
ZZPY
grep -q "cgit.git.savannah.gnu.org" PKGBUILD && {
    echo "autoconf-archive: a cgit URL survived" >&2; exit 1; }
grep -qE "github.com/autoconf-archive/autoconf-archive/commit/[0-9a-f]{40}\.patch" PKGBUILD || {
    echo "autoconf-archive: the mirror URL is malformed" >&2; exit 1; }
echo "autoconf-archive: patch taken from the git mirror (same commit)"
