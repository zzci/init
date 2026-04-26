#!/bin/bash
# COPY --from=zzci/init / / into a different base image (alpine).
# - alpine userland is preserved
# - zzci/init layer (start.sh, sctl, supervisord, tini, busybox) overlays cleanly
# - PATH is self-exported by start.sh so init system works without ENV PATH

set -uo pipefail
. "$(dirname "$0")/../lib.sh"

INJECT_TAG=zzci/init:e2e-inject
INJECT_CTX=$(mkwork)

cat > "$INJECT_CTX/Dockerfile" <<EOF
FROM alpine:3.20
COPY --from=$IMAGE / /
COPY web.conf /build/services/
CMD ["/start.sh"]
EOF

cat > "$INJECT_CTX/web.conf" <<'EOF'
[program:web]
command=/build/bin/busybox/sleep 600
autostart=true
EOF

docker build -q -t "$INJECT_TAG" "$INJECT_CTX" >/dev/null

cid=$(docker run --rm -d -e ZSRV_web=true "$INJECT_TAG")
trap "stop_ctr $cid; docker rmi -f $INJECT_TAG >/dev/null 2>&1" EXIT
wait_ready "$cid" || { echo "supervisord not ready in injected image"; exit 1; }

fail=0
assert_eq "web is active in injected image" "web" "$(list_active "$cid")" || fail=1
if wait_program_running "$cid" web; then
    printf "    [ok] %s\n" "web reached Running in injected image"
else
    printf "    [FAIL] web never reached Running (state=%s)\n" "$(proc_state "$cid" web)"
    fail=1
fi

# Confirm alpine userland is intact (apk exists, not from busybox).
apk_out=$(docker exec "$cid" apk --version 2>&1 | head -1)
assert_contains "alpine apk still works after injection" "apk-tools" "$apk_out" || fail=1

# Confirm zzci/init absolute paths are reachable.
docker exec "$cid" /build/bin/busybox/test -x /build/bin/supervisord
docker exec "$cid" /build/bin/busybox/test -x /build/bin/tini
docker exec "$cid" /build/bin/busybox/test -x /build/bin/sctl
printf "    [ok] %s\n" "/build/bin binaries present and executable"

exit $fail
