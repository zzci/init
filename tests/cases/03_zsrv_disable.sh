#!/bin/bash
# ZSRV_<name>=false:
#   - moves run/<name>.conf to run/.disabled/<name>.conf (file preserved)
#   - works for both template-derived AND pre-baked services
#   - service is not loaded by supervisord

set -uo pipefail
. "$(dirname "$0")/../lib.sh"

work=$(mkwork)
srv_template "$work" web
srv_run      "$work" prebaked

cid=$(start_ctr "$work" \
    -e ZSRV_web=true \
    -e ZSRV_prebaked=false)
trap "stop_ctr $cid" EXIT

wait_ready "$cid" || { echo "supervisord did not become ready"; exit 1; }

fail=0
assert_eq "only web is active" "web" "$(list_active "$cid")" || fail=1
assert_eq "prebaked is in disabled list" "prebaked" "$(list_disabled "$cid")" || fail=1
assert_file "disabled file exists in .disabled/" "$cid" "/.init/services/run/.disabled/prebaked.conf" || fail=1
assert_no_file "original run/ entry removed" "$cid" "/.init/services/run/prebaked.conf" || fail=1

# false-y synonyms should all skip
work2=$(mkwork)
srv_template "$work2" foo
srv_template "$work2" bar
srv_template "$work2" baz
cid2=$(start_ctr "$work2" \
    -e ZSRV_foo=0 \
    -e ZSRV_bar=no \
    -e ZSRV_baz=off)
trap "stop_ctr $cid; stop_ctr $cid2" EXIT
wait_ready "$cid2" || { echo "second container not ready"; exit 1; }
assert_eq "false-y synonyms (0/no/off) all skip" "" "$(list_active "$cid2")" || fail=1

exit $fail
