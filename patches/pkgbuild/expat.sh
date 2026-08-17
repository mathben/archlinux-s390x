#!/usr/bin/env bash
# expat: two defaults decided by the build HOST rather than by the PKGBUILD.
set -euo pipefail

# 1. The library directory.
#
# The PKGBUILD calls cmake directly -- NOT arch-cmake -- so the devtools
# stand-in that already passes -DCMAKE_INSTALL_LIBDIR=lib never runs. The
# option array only pins the prefix.
#
# expat's CMakeLists include(GNUInstallDirs), and GNUInstallDirs picks its
# default LIBDIR by sniffing the HOST: it sees /etc/debian_version, finds no
# /etc/arch-release, and sets lib/<multiarch> = lib/s390x-linux-gnu. Because
# CMAKE_INSTALL_LIBDIR was never given, that default wins and is cached.
#
# The build then exits 0 and the package installs cleanly. It is the ARTEFACT
# that is wrong -- everything LIBDIR-derived lands off Arch's search paths:
#
#   usr/lib/s390x-linux-gnu/libexpat.so.1.12.3   ld.so reads /usr/lib only
#   usr/lib/s390x-linux-gnu/pkgconfig/expat.pc   pkgconf reads /usr/lib only
#   usr/lib/s390x-linux-gnu/cmake/expat-2.8.3/   find_package(EXPAT) misses
#
# and usr/lib itself holds nothing but that subdirectory. expat is a
# dependency of cmake, python, gdb and fontconfig, so this does not fail
# loudly here -- it fails later, in whatever links against -lexpat.
#
# Passing it on the command line makes it a cache entry BEFORE GNUInstallDirs
# runs, and GNUInstallDirs only fills in defaults for variables still unset.
python3 - <<'PY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()
assert "CMAKE_INSTALL_LIBDIR" not in s, "expat: libdir already set, hook ran twice"
anchor = "    -D CMAKE_INSTALL_PREFIX=/usr\n"
n = s.count(anchor)
assert n == 1, "expat: expected 1 cmake option block, found %d" % n
s = s.replace(anchor, anchor + "    -D CMAKE_INSTALL_LIBDIR=lib\n", 1)
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
PY
[ "$(grep -c 'CMAKE_INSTALL_LIBDIR=lib' PKGBUILD)" = 1 ] || {
    echo "expat: libdir not pinned exactly once" >&2; exit 1; }
echo "expat: CMAKE_INSTALL_LIBDIR=lib (bare cmake bypasses arch-cmake)"

# 2. EXPAT_BUILD_DOCS: pin it OFF, because its default reads the host's PATH.
#
# THE TRAP: this option has no fixed default. CMakeLists.txt line 74 does
#
#   find_program(DOCBOOK_TO_MAN NAMES docbook2x-man db2x_docbook2man \
#                                     docbook2man docbook-to-man)
#
# and turns docs ON if ANY of those four is found. Nothing in the PKGBUILD
# asks for docs -- makedepends is (cmake git). So whether expat builds a man
# page is decided by whatever apt happens to have dragged onto the VM.
#
# Not hypothetical, and the timeline is the whole lesson. expat built clean on
# 2026-08-15 21:25 and its package carries no usr/share/man at all. At
# 2026-08-16 00:23:31 apt installed docbook-utils -- nobody asked for it; it
# arrived as an automatic dependency of asciidoc, which install_host_deps
# needs for pacman. docbook-utils owns /usr/bin/docbook2man, the THIRD name in
# that list. From that moment find_program succeeded and a target that had
# never run in this port switched itself on. expat was simply not rebuilt for
# another twenty-nine hours, so the breakage waited.
#
# THE ERROR NAMES THE WRONG CULPRIT, twice over:
#
#   mv: cannot stat 'XMLWF.1': No such file or directory
#
# Nothing is wrong with the mv, and XMLWF.1 is the correct name --
# doc/xmlwf.xml declares <refentrytitle>XMLWF</refentrytitle>, and every
# docbook man backend derives the filename from it. The real failure is one
# command earlier and silent: docbook-utils' docbook2man is a two-line shell
# script, `jw -f docbook -b man "$@"`, i.e. the SGML pipeline. doc/xmlwf.xml
# is DocBook XML 4.2, whose ISO entity sets use `&#xNNNN;` hex character
# references that SGML forbids. onsgmls emits `"X2288" is not a function name`
# two hundred times, gives up -- and jw still EXITS 0, having written only
# manpage.refs and manpage.links. Those two hundred lines sit ABOVE the
# failure in the log and read like harmless validation noise.
#
# Upstream knows this tool is unusable and rejects it BY NAME in the autotools
# path: configure.ac:454 greps `${DOCBOOK_TO_MAN} --help` for "sgmlbase" and
# aborts with "was found to work with SGML rather than XML". Our
# /usr/bin/docbook2man matches that grep. The CMake path has no such guard.
#
# WHY OFF RATHER THAN INSTALLING docbook2x: because OFF is what Arch ships.
# Arch's core expat 2.8.3 has 29 files and no usr/share/man, which proves
# Arch's builder has none of those four programs -- any one would have flipped
# the default. Pinning OFF reproduces Arch exactly; installing docbook2x would
# make s390x diverge from x86_64 and add one more host tool that silently
# decides what gets built.
python3 - <<'PY'
import io
s = io.open("PKGBUILD", encoding="utf-8").read()
assert "EXPAT_BUILD_DOCS" not in s, "expat: docs already pinned, hook ran twice"
anchor = "    -D CMAKE_INSTALL_LIBDIR=lib\n"
n = s.count(anchor)
assert n == 1, "expat: expected 1 libdir line, found %d" % n
s = s.replace(anchor, anchor + "    -D EXPAT_BUILD_DOCS=OFF\n", 1)
io.open("PKGBUILD", "w", encoding="utf-8").write(s)
PY
[ "$(grep -c 'EXPAT_BUILD_DOCS=OFF' PKGBUILD)" = 1 ] || {
    echo "expat: docs not pinned exactly once" >&2; exit 1; }
echo "expat: EXPAT_BUILD_DOCS=OFF (default follows host PATH, not the PKGBUILD)"
