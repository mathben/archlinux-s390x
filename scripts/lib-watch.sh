#!/usr/bin/env bash
# The stall guard, and nothing else.
#
# WHY ITS OWN FILE. It belongs to both stages, so the obvious home was
# bootstrap-pacman.sh, which stage 1 already sources. Stage 2 cannot source
# that file: it opens with `set -euo pipefail`, and stage 2's whole rebuild
# loop depends on a failed package NOT ending the run -- one missing package
# must not hide the state of the hundred that follow. It also defines a main(),
# which is a second thing to be careful about for no benefit.
#
# So: one file, no `set -e`, no side effects, sourced by both. Nothing else
# goes in here.

# Run a command, and kill it if it stops saying anything.
#
#   watched <logfile> <command...>
#
# Returns the command's status, or 2 if it was killed for silence.
#
# WHY IT EXISTS. python's build ran for ten hours. It was not slow: it was
# spinning in a shell loop waiting for an X server that this port will never
# have, printing nothing. Nothing distinguished it from a long compile except
# that the log had not grown -- and that is a measurement, so it can be made
# automatically.
#
# Both stages need it, and stage 2 needs it MORE: stage 2 runs the test suites
# that stage 1 skipped, and a test suite is the likeliest thing in a build to
# wait forever on a terminal, a network socket, or a display.
#
# Killed as a PROCESS GROUP -- set -m gives the subshell its own, so make and
# every compiler under it die too. Killing the pid alone leaves the tree
# running, holding the disk, invisible to the driver that thinks it stopped it.
watched() {
    local log="$1"; shift
    local limit="${EL_STALL_MIN:-45}"
    if [ "$limit" -eq 0 ]; then
        "$@" > "$log" 2>&1
        return $?
    fi
    set -m
    ( "$@" ) > "$log" 2>&1 &
    local pid=$! last=0 still=0 sz
    set +m
    while kill -0 "$pid" 2>/dev/null; do
        sleep 60
        sz=$(stat -c %s "$log" 2>/dev/null || echo 0)
        if [ "$sz" -eq "$last" ]; then still=$((still + 1)); else still=0; fi
        last="$sz"
        if [ "$still" -ge "$limit" ]; then
            printf '\n== driver: no output for %s minutes, killing ==\n' "$limit" >> "$log"
            kill -9 -- "-$pid" 2>/dev/null
            wait "$pid" 2>/dev/null
            return 2
        fi
    done
    wait "$pid"
}
