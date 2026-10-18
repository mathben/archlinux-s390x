#!/usr/bin/env bash
# prepare() prefetches its crates against a placeholder target. The reasoning,
# and the edit, are shared -- see lib-cargo-host-tuple.sh.
set -euo pipefail
source "$(dirname "$0")/lib-cargo-host-tuple.sh"
