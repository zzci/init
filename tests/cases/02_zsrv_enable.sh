#!/bin/bash
# All ZSRV_ enable variants:
#   ZSRV_<name>=true    -> suffix as name
#   ZSRV_<name>=        -> empty value, suffix as name
#   ZSRV_<key>=<name>   -> value as name (works for hyphenated names)
#   pre-baked in run/   -> active without any ZSRV_

set -uo pipefail
. "$(dirname "$0")/../lib.sh"

work=$(mkwork)
srv_template "$work" web
srv_template "$work" api
srv_template "$work" web-http
srv_run      "$work" prebaked

cid=$(start_ctr "$work" \
    -e ZSRV_web=true \
    -e ZSRV_api= \
    -e ZSRV_HTTP=web-http)
trap "stop_ctr $cid" EXIT

wait_ready "$cid" || { echo "supervisord did not become ready"; exit 1; }

active=$(list_active "$cid")
expected=$'api\nprebaked\nweb\nweb-http'

fail=0
assert_eq "all four enabled (incl. hyphen + pre-baked)" "$expected" "$active" || fail=1

for n in web web-http prebaked; do
    if wait_program_running "$cid" "$n"; then
        printf "    [ok] %s\n" "$n reached Running"
    else
        printf "    [FAIL] %s never reached Running (state=%s)\n" \
            "$n" "$(proc_state "$cid" "$n")"
        fail=1
    fi
done

exit $fail
