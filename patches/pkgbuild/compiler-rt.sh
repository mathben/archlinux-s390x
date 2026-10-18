#!/usr/bin/env bash
# compiler-rt: llvm-libc believes s390x has __float128. It does not.
#
# THE FAILURE. compiler-rt compiles headers from llvm-libc, and one of them
# stops the build outright:
#
#   cfloat128.h:18: error: expected primary-expression before '_Complex'
#   is_complex.h:44: error: 'cfloat128' was not declared in this scope
#
# WHY. cfloat128-macros.h decides whether the platform has a 128-bit complex
# type, and its GNU branch accepts either of two signals:
#
#   #if (defined(__STDC_IEC_60559_COMPLEX__) || defined(__SIZEOF_FLOAT128__))
#
# On s390x the FIRST is defined and the second is not: the architecture does
# have IEEE 128-bit complex arithmetic, but it reaches it through `long
# double`, and `__float128` is an x86 spelling that does not exist here. The
# macro is therefore defined, and the typedef under it asks for
# `_Complex __float128` -- a type nothing declares.
#
# THE FIX IS THE CONDITION, NOT THE TYPEDEF. Requiring __SIZEOF_FLOAT128__
# alone lets the third branch of the same file take over:
#
#   #if !defined(LIBC_TYPES_HAS_CFLOAT128) && (LDBL_MANT_DIG == 113)
#   #define LIBC_TYPES_CFLOAT128_IS_COMPLEX_LONG_DOUBLE
#
# which is exactly right for s390x -- 113 mantissa bits, complex long double.
# The file already knows how to describe this architecture; the earlier branch
# was simply reached first. Nothing is disabled and no feature is lost.
#
# WHY THE EDIT LIVES IN prepare() AND NOT HERE. A hook runs on the PKGBUILD
# before makepkg has extracted anything: there is no src/ yet to patch. What a
# hook can do is put the edit where the sources will exist.
#
# TO CLOSE: upstream. The condition is wrong for every architecture with IEEE
# 128-bit long double and no __float128, s390x being one of them.
set -euo pipefail
python3 - <<'ZZPY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()

# ANCRÉ SUR UNE LIGNE, PAS SUR UN BLOC.
#
# Ce crochet remplaçait les quatre lignes entières de prepare(). L amont y a
# inséré un `patch -Np1 -i ...`, et le bloc littéral a cessé d exister :
#
#   AssertionError: compiler-rt: prepare() introuvable
#
# après des heures de construction, en accusant une fonction qui est bien là.
# Seule `mkdir build` compte ici : le correctif se pose juste avant elle, et
# ce que l amont ajoute autour survit.
anchor = "\n  mkdir build\n"
assert s.count(anchor) == 1, "compiler-rt: la ligne `mkdir build` n est pas unique"
fix = """
  # s390x has IEEE 128-bit complex through long double and no __float128;
  # llvm-libc's GNU branch accepts either signal and then requires the type
  # that is missing. See patches/pkgbuild/compiler-rt.sh.
  # Le delimiteur est %, pas | : le motif contient les || du C, et un | y
  # terminerait l expression -- « sed: unknown option to 's' ». Seul le
  # premier test disparait ; le && et la suite de la ligne restent.
  # UPSTREAM MAY HAVE DONE IT ALREADY, and the test belongs here rather than
  # in the hook: a hook runs beside the PKGBUILD, before the sources are
  # unpacked, with no header to read. A release spelling the gate with && and
  # no || already requires the macro this patch exists to require, so there is
  # nothing to change and the build goes on. Failing there would block the
  # package over a fix landing upstream. A third spelling stops the build
  # rather than guessing which half to keep.
  _h=../libc/include/llvm-libc-macros/cfloat128-macros.h
  if grep -q 'defined(__STDC_IEC_60559_COMPLEX__) || ' "$_h"; then
    sed -i 's%defined(__STDC_IEC_60559_COMPLEX__) || %%' "$_h"
    grep -q '__STDC_IEC_60559_COMPLEX__' "$_h" \\
      && { echo 'compiler-rt: la condition trop large survit' >&2; exit 1; }
  elif ! grep -q 'defined(__STDC_IEC_60559_COMPLEX__) && defined(__SIZEOF_FLOAT128__)' "$_h"; then
    echo 'compiler-rt: gabarit cfloat128 inconnu, ni || ni &&' >&2; exit 1
  fi
  mkdir build
"""
s = s.replace(anchor, fix, 1)


io.open("PKGBUILD", "w", encoding="utf-8").write(s)
ZZPY
grep -q "cfloat128-macros.h" PKGBUILD || {
    echo "compiler-rt: le correctif n a pas ete pose" >&2; exit 1; }
grep -q "mkdir build" PKGBUILD || {
    echo "compiler-rt: le repertoire de construction a disparu" >&2; exit 1; }
echo "compiler-rt: cfloat128 exigera __SIZEOF_FLOAT128__"
