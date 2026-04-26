#!/bin/bash
# Run all e2e tests under cases/.
#
# Usage: ./run.sh [pattern]
#   pattern: optional shell glob to filter case files (e.g. ./run.sh '03*')
#
# Env:
#   IMAGE     image tag to build (default: zzci/init:e2e)
#   TMP_BASE  scratch dir for per-test work mounts (default: ./tests/.tmp)
#   KEEP=1    keep TMP_BASE after run (for debugging)

set -uo pipefail

cd "$(dirname "$0")"
. ./lib.sh

PATTERN=${1:-'*.sh'}

echo "==> Building image $IMAGE"
build_image

PASS=0
FAIL=0
FAILED=()

for f in cases/$PATTERN; do
    [ -f "$f" ] || continue
    name=$(basename "$f" .sh)
    echo
    echo "==> $name"
    if bash "$f"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        FAILED+=("$name")
    fi
done

echo
echo "================================================================"
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then
    echo "Failed cases:"
    for n in "${FAILED[@]}"; do echo "  - $n"; done
fi

if [ "${KEEP:-0}" != "1" ]; then
    rm -rf "$TMP_BASE"
fi

[ $FAIL -eq 0 ]
