#!/bin/bash
# sctl runtime commands:
#   list      -> shows runtime state from supervisord + filesystem
#   enable    -> live add (ctl reload picks up + autostart fires)
#   disable   -> live stop (ctl reload removes program)
#   restart   -> stop+start
#   show      -> single-service status

set -uo pipefail
. "$(dirname "$0")/../lib.sh"

work=$(mkwork)
srv_template "$work" web
srv_template "$work" api
srv_template "$work" redis

cid=$(start_ctr "$work" -e ZSRV_web=true -e ZSRV_api=true)
trap "stop_ctr $cid" EXIT
wait_ready "$cid" || { echo "supervisord did not become ready"; exit 1; }

fail=0

wait_program_running "$cid" web && wait_program_running "$cid" api

# Initial state: web + api active, redis only as template
assert_eq "initial active set" $'api\nweb' "$(list_active "$cid")" || fail=1
templates=$(list_templates "$cid")
assert_contains "templates includes redis" "redis" "$templates" || fail=1

# sctl disable web -> file moves, supervisord stops it via ctl reload
docker exec "$cid" /build/bin/sctl disable web >/dev/null
sleep 0.5
assert_eq "after disable, only api active" "api" "$(list_active "$cid")" || fail=1
assert_eq "web in disabled" "web" "$(list_disabled "$cid")" || fail=1

# sctl enable redis -> redis starts (live)
docker exec "$cid" /build/bin/sctl enable redis >/dev/null
wait_program_running "$cid" redis || true
active=$(list_active "$cid")
assert_contains "after enable redis, redis is active" "redis" "$active" || fail=1
assert_eq "redis is Running" "Running" "$(proc_state "$cid" redis)" || fail=1

# sctl enable web -> restore from .disabled/
docker exec "$cid" /build/bin/sctl enable web >/dev/null
wait_program_running "$cid" web || true
assert_eq "web restored to active" "Running" "$(proc_state "$cid" web)" || fail=1
assert_eq "disabled list now empty" "" "$(list_disabled "$cid")" || fail=1

# sctl restart api -> pid changes
get_pid() {
    local out
    out=$(docker exec "$cid" /build/bin/sctl show api 2>/dev/null) || true
    printf '%s\n' "$out" | strip_ansi | grep -oE 'pid [0-9]+' | awk '{print $2; exit}'
}
old_pid=$(get_pid)
docker exec "$cid" /build/bin/sctl restart api >/dev/null 2>&1 || true
sleep 1
new_pid=$(get_pid)
if [ -n "$old_pid" ] && [ -n "$new_pid" ] && [ "$old_pid" != "$new_pid" ]; then
    printf "    [ok] %s\n" "restart changed pid ($old_pid -> $new_pid)"
else
    printf "    [FAIL] restart did not change pid (old=%s new=%s)\n" "$old_pid" "$new_pid"
    fail=1
fi

# sctl show NAME returns line for that program
show_out=$(docker exec "$cid" /build/bin/sctl show web 2>/dev/null) || true
show_out=$(printf '%s\n' "$show_out" | strip_ansi)
assert_contains "show web mentions web" "web" "$show_out" || fail=1

exit $fail
