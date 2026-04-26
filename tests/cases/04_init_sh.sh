#!/bin/bash
# /work/.init/init.sh runs before supervisord, and ZSRV_ env vars run
# AFTER init.sh so deployment-time env vars are the final authority.
#
# Scenario: init.sh enables web; ZSRV_web=false then disables it.
# Expected: web ends up disabled, init.sh's enable was overridden.

set -uo pipefail
. "$(dirname "$0")/../lib.sh"

work=$(mkwork)
srv_template "$work" web
srv_template "$work" redis
init_hook "$work" <<'EOF'
echo "[init.sh] running custom hook"
sctl enable web
sctl enable redis
EOF

cid=$(start_ctr "$work" -e ZSRV_web=false)
trap "stop_ctr $cid" EXIT
wait_ready "$cid" || { echo "supervisord did not become ready"; exit 1; }

logs=$(docker logs "$cid" 2>&1)
fail=0
assert_contains "init.sh hook executed" "[init.sh] running custom hook" "$logs" || fail=1
assert_eq "redis stays active (no override)" "redis" "$(list_active "$cid")" || fail=1
assert_eq "web ended up disabled" "web" "$(list_disabled "$cid")" || fail=1

# Verify the order in logs: init.sh ran BEFORE the disable.
init_line=$(echo "$logs" | grep -n '\[init.sh\]' | head -1 | cut -d: -f1)
disabled_line=$(echo "$logs" | grep -n 'disabled service via env: web' | head -1 | cut -d: -f1)
if [ -n "$init_line" ] && [ -n "$disabled_line" ] && [ "$init_line" -lt "$disabled_line" ]; then
    printf "    [ok] %s\n" "init.sh ran before ZSRV processing"
else
    printf "    [FAIL] init.sh order (init=%s disable=%s)\n" "$init_line" "$disabled_line"
    fail=1
fi

exit $fail
