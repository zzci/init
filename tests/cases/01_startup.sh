#!/bin/bash
# Container boots cleanly with no services and tolerates missing ZSRV configs.

set -uo pipefail
. "$(dirname "$0")/../lib.sh"

work=$(mkwork)
cid=$(start_ctr "$work" -e ZSRV_missing=true)
trap "stop_ctr $cid" EXIT

wait_ready "$cid" || { echo "supervisord did not become ready"; exit 1; }

logs=$(docker logs "$cid" 2>&1)
fail=0
assert_contains "missing config logs warning" "service config not found: missing" "$logs" || fail=1
assert_eq "no active services" "" "$(list_active "$cid")" || fail=1
assert_eq "container still running" "true" "$(docker inspect -f '{{.State.Running}}' "$cid")" || fail=1

exit $fail
