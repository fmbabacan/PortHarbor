#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SCRATCH=/tmp/PortHarbor-performance
RESULT=/tmp/portharbor-performance-test.txt

rm -rf "$SCRATCH"
# Build and exercise the isolated live test before timing its warm runtime path.
# Dependency resolution and compiler cache state are not runtime latency.
PORTHARBOR_LIVE_TEST=1 swift test \
    --package-path "$ROOT" \
    --scratch-path "$SCRATCH" \
    --filter liveProviderDiscoversCurrentMacListeners \
    > "$RESULT" 2>&1

START_NS=$(python3 -c 'import time; print(time.time_ns())')
PORTHARBOR_LIVE_TEST=1 swift test \
    --package-path "$ROOT" \
    --scratch-path "$SCRATCH" \
    --skip-build \
    --filter liveProviderDiscoversCurrentMacListeners \
    >> "$RESULT" 2>&1
END_NS=$(python3 -c 'import time; print(time.time_ns())')
ELAPSED=$(python3 -c "print(($END_NS - $START_NS) / 1000000000)")

grep -F 'liveProviderDiscoversCurrentMacListeners() passed' "$RESULT" > /dev/null
if grep -F 'liveProviderDiscoversCurrentMacListeners() skipped' "$RESULT" > /dev/null; then
    printf '%s\n' 'Live listener test was skipped.' >&2
    exit 1
fi

python3 -c "import sys; value=float('$ELAPSED'); sys.exit(0 if value < 20 else 1)"
printf 'Live listener smoke completed in %s seconds.\n' "$ELAPSED"
