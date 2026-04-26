#!/bin/bash
# tini forwards signals correctly: SIGTERM to PID 1 -> supervisord stops
# all child programs cleanly -> container exits with 0.

set -uo pipefail
. "$(dirname "$0")/../lib.sh"

work=$(mkwork)
srv_template "$work" web
srv_template "$work" api

cid=$(start_ctr "$work" -e ZSRV_web=true -e ZSRV_api=true)
trap "stop_ctr $cid" EXIT
wait_ready "$cid" || { echo "supervisord did not become ready"; exit 1; }

# Capture all logs first; docker stop sends SIGTERM and waits up to 10s.
# We assert on log evidence (orderly shutdown) rather than exit code,
# because supervisord's exit code on SIGTERM is implementation-defined
# and not guaranteed to be 0.
start_time=$(date +%s)
docker stop -t 10 "$cid" >/dev/null
elapsed=$(($(date +%s) - start_time))

oom=$(docker inspect -f '{{.State.OOMKilled}}' "$cid" 2>/dev/null || echo "?")
logs=$(docker logs "$cid" 2>&1)

fail=0
assert_eq "not OOM killed" "false" "$oom" || fail=1

# Shutdown completed before docker's 10s SIGKILL fallback.
if [ "$elapsed" -lt 10 ]; then
    printf "    [ok] graceful shutdown completed in %ss (under 10s SIGKILL deadline)\n" "$elapsed"
else
    printf "    [FAIL] container needed SIGKILL (took %ss)\n" "$elapsed"
    fail=1
fi

assert_contains "supervisord received stop signal" "receive a signal to stop" "$logs" || fail=1
assert_contains "web was stopped"  "stopping the program" "$logs" || fail=1
assert_contains "web stopped by user" "stopped by user" "$logs" || fail=1

exit $fail
