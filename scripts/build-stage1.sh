#!/usr/bin/env bash
# Stage 1 of the port: build a self-hosting Arch `core` for s390x.
#
# THE THREE-STAGE DISCIPLINE, AND WHY IT IS NOT OPTIONAL
#
# Stage 1 builds with the HOST toolchain (Ubuntu gcc/glibc). Every package it
# produces is therefore linked against the host's glibc, not Arch's. That is
# acceptable -- and unavoidable, since Arch's glibc needs an Arch gcc which
# needs an Arch glibc -- but it is not a port yet.
#
# Stage 2 chroots into the stage-1 result and rebuilds everything with the
# stage-1 toolchain. Stage 3 repeats it, and a port is self-hosting once
# stage 3 reproduces stage 2. Skipping this leaves host artefacts baked into
# packages that will fail months later, far from their cause.
#
# This script is stage 1 only.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/bootstrap-pacman.sh"
source "$HERE/lib-watch.sh"

WORK="${WORK:-$HOME/work/arch-s390x}"
REPO="${REPO:-$WORK/repo/s390x}"
STATE="$WORK/stage1.state"

# Build order. It follows link-time dependencies, not pacman metadata:
# --nodeps means pacman never checks, so anything a compiler actually needs
# must already exist. Within a group the order is free.
# The list and its order live in one file, read by both stages -- see the
# header of packages.sh for why stage 2 must not derive its own.
source "$HERE/packages.sh"

# Kill a build that has stopped producing output.
#
# WHY THIS EXISTS. python's PKGBUILD contains
#
#   while ! xvfb-run -a -n "$servernum" /bin/true 2>/dev/null; do
#       servernum=$((servernum+1)); done
#
# and xvfb-run is not installed here. It exits 127, `!` inverts that to true,
# and the loop tries the next display number. Forever -- there is no exit
# condition for "the command does not exist", and the 2>/dev/null swallows the
# one line that would have said so.
#
# Measured before anyone noticed: TEN HOURS of wall clock, four million PIDs,
# and a log frozen at `configure: creating Makefile`. Every signal I had said
# the build was healthy -- the process was alive, burning 40% CPU, sitting in
# a plausible source directory. A process list cannot tell work from spinning.
#
# A STALLED LOG NEXT TO A LIVE makepkg CAN. That is the whole idea here.
#
# The threshold is deliberately generous. Real builds do go quiet: a long link,
# a test suite that prints nothing, gcc between bootstrap stages. Forty-five
# minutes of COMPLETE silence is not one of those, and the case this was
# written for ran two hundred times longer. EL_STALL_MIN=0 disables it.
#
# `set -m` rather than setsid or a bare `&`. The whole tree has to die, because
# makepkg forks children that outlive it -- killing the parent alone leaves
# them spinning, which is how ten hours happened. Job control gives the
# background job its own process group, so `kill -- -$pid` reaches all of it.
#
# A subshell, NOT `setsid bash -c "$(declare -f ...)"`. The first attempt here
# re-declared build_package into a fresh shell, which loses $WORK, $REPO,
# $PATCH_DIR and every other function it calls -- a guard that would have
# broken the thing it was guarding.
# The stall guard moved to bootstrap-pacman.sh when stage 2 needed it too.
build_watched() { watched "$2" build_package "$1"; }

built() { grep -qxF "$1" "$STATE" 2>/dev/null; }
# Appended only once: a forced rebuild of an already-built package must not
# leave two identical lines in the state file. built() uses grep -qxF, so a
# duplicate is harmless to the logic and confusing to a reader counting lines.
mark()  { built "$1" || echo "$1" >> "$STATE"; }

main() {
    mkdir -p "$WORK/pkg" "$REPO"
    touch "$STATE"
    # The stand-ins are read from /usr/local/bin, so a stage-1 run that never
    # reinstalls them silently builds with whatever was deployed weeks ago.
    # Cheap, idempotent, and it makes this repository the source of truth.
    install_host_shims
    # Named packages rebuild on demand, the way stage 2 already works.
    #
    # Without this, rebuilding one package means deleting its line from
    # stage1.state first -- editing the record of what was built in order to
    # build something. That file is the port's memory; the opening instruction
    # for this work is to regenerate it from what is REALLY in repo/s390x and
    # never from a log, and hand-editing it is the same mistake in a smaller
    # form. Naming a package is also how a hook gets tested: libarchive's xar
    # fix needed exactly one package rebuilt, not a pass over a hundred and
    # ninety.
    local list=("${STAGE1_PACKAGES[@]}") forced=0
    if [ "$#" -gt 0 ]; then
        list=("$@")
        forced=1
        printf '== stage 1: rebuilding on request: %s ==\n' "$*"
    fi
    local ok=0 fail=0 rc=0 failed=()
    for p in "${list[@]}"; do
        # An explicit request outranks the state file. Asking for a package
        # that is already built and being told it was skipped would make the
        # command useless for the one job it exists to do.
        if [ "$forced" -eq 0 ] && built "$p"; then
            echo "== $p already built, skipping =="
            continue
        fi
        # A failure must not stop the run: one missing package should not hide
        # the state of the forty that follow. They are collected and reported.
        if build_watched "$p" "$WORK/log-$p.txt"; then
            mark "$p"; ok=$((ok + 1))
            install_host_python_module "$p"
            echo "OK    $p"
        else
            rc=$?
            fail=$((fail + 1)); failed+=("$p")
            if [ "$rc" -eq 2 ]; then
                echo "STALL $p  (no output for ${EL_STALL_MIN:-45} min, killed)"
            else
                echo "FAIL  $p  (see $WORK/log-$p.txt)"
            fi
        fi
    done
    echo
    echo "== stage 1: $ok built, $fail failed =="
    # A stage-1 run is never expected to be clean: seven packages cannot build
    # outside the chroot, and their names are recorded in packages.sh. Printing
    # one undifferentiated list makes a reader compare it against prose every
    # time, and a real regression hides among names that belong there.
    local expected=() unexpected=()
    local p q
    for p in "${failed[@]}"; do
        local known=0
        for q in "${STAGE1_EXPECTED_FAILURES[@]}"; do
            [ "$p" = "$q" ] && { known=1; break; }
        done
        if [ "$known" -eq 1 ]; then expected+=("$p"); else unexpected+=("$p"); fi
    done
    [ "${#expected[@]}" -eq 0 ] || \
        printf '  expected (see STAGE1_EXPECTED_FAILURES): %s\n' "${expected[*]}"
    if [ "${#unexpected[@]}" -eq 0 ]; then
        [ "$fail" -eq 0 ] || echo "  no unexpected failure"
    else
        printf '  UNEXPECTED: %s\n' "${unexpected[*]}"
    fi
    # An expected failure that stopped happening is news too: the list is wrong
    # from that moment, and saying so is what keeps it from drifting into prose
    # nobody rechecks.
    for q in "${STAGE1_EXPECTED_FAILURES[@]}"; do
        built "$q" && printf '  now builds, drop it from STAGE1_EXPECTED_FAILURES: %s\n' "$q"
    done
}

main "$@"
