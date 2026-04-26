#!/bin/bash
# Shared helpers for e2e tests. Source this from each case file.

set -euo pipefail

LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$LIB_DIR/.." && pwd)
IMAGE=${IMAGE:-zzci/init:e2e}
TMP_BASE=${TMP_BASE:-$LIB_DIR/.tmp}

mkdir -p "$TMP_BASE"

# --- container lifecycle ---------------------------------------------------

build_image() {
    docker build -q -t "$IMAGE" "$ROOT" >/dev/null
}

# Make a fresh, unique work dir for one test run.
mkwork() {
    mktemp -d -p "$TMP_BASE" work.XXXXXX
}

# Drop a service template at /work/.init/services/<name>.conf.
srv_template() {
    local work=$1 name=$2
    mkdir -p "$work/.init/services"
    cat > "$work/.init/services/$name.conf" <<EOF
[program:$name]
command=/build/bin/busybox/sleep 600
autostart=true
EOF
}

# Drop a service config straight into /work/.init/services/run/<name>.conf
# (pre-baked, no enable step needed).
srv_run() {
    local work=$1 name=$2
    mkdir -p "$work/.init/services/run"
    cat > "$work/.init/services/run/$name.conf" <<EOF
[program:$name]
command=/build/bin/busybox/sleep 600
autostart=true
EOF
}

# Write a /work/.init/init.sh hook with arbitrary body.
init_hook() {
    local work=$1
    mkdir -p "$work/.init"
    cat > "$work/.init/init.sh"
    chmod +x "$work/.init/init.sh"
}

# Start container detached, return container id.
# We deliberately don't use --rm so logs survive `docker stop` for assertions.
# Cleanup happens via stop_ctr (docker rm -f) in each case's EXIT trap.
start_ctr() {
    local work=$1
    shift
    docker run -d -v "$work:/work" "$@" "$IMAGE"
}

# Wait until sctl returns active section (supervisord ctl is responsive).
# Returns 0 on ready, 1 on timeout (5s).
#
# Note: capture into a var before grep. With `set -o pipefail`, an
# early-exiting consumer (grep -q, head, etc.) causes SIGPIPE on the
# upstream `docker exec`, making the whole pipeline return non-zero
# even when the match succeeded.
wait_ready() {
    local cid=$1 i out
    for i in $(seq 1 25); do
        out=$(docker exec "$cid" /build/bin/sctl list 2>/dev/null) || true
        if printf '%s\n' "$out" | grep -q '^\[active\]'; then
            return 0
        fi
        sleep 0.2
    done
    return 1
}

# Wait until a program reaches Running state (past startsecs).
# Returns 0 on success, 1 on timeout.
wait_program_running() {
    local cid=$1 name=$2 i
    for i in $(seq 1 25); do
        if [ "$(proc_state "$cid" "$name")" = "Running" ]; then
            return 0
        fi
        sleep 0.2
    done
    return 1
}

stop_ctr() {
    docker rm -f "$1" >/dev/null 2>&1 || true
}

# --- inspection helpers ----------------------------------------------------

# Strip ANSI color codes.
strip_ansi() {
    sed -E $'s/\x1b\\[[0-9;]*m//g'
}

# Run sctl list once and stash output (avoid repeated docker exec round trips).
sctl_list_raw() {
    local cid=$1 out
    out=$(docker exec "$cid" /build/bin/sctl list 2>/dev/null) || true
    printf '%s\n' "$out"
}

_section_names() {
    local section=$1
    awk -v s="^\\[$section\\]" '
        $0 ~ s {f=1; next}
        /^\[/ {f=0}
        f {print $1}
    ' | grep -v '^$' | sort -u || true
}

# List active service names (one per line, sorted).
list_active() {
    sctl_list_raw "$1" | strip_ansi | _section_names active
}

# List disabled service names.
list_disabled() {
    sctl_list_raw "$1" | _section_names disabled
}

# List template service names.
list_templates() {
    sctl_list_raw "$1" | _section_names templates
}

# Get supervisord process state (Running/Stopped/etc) for one program.
# Capture into var first to avoid SIGPIPE under `set -o pipefail` when
# head -1 closes early.
proc_state() {
    local cid=$1 name=$2 out
    out=$(docker exec "$cid" /build/bin/sctl show "$name" 2>/dev/null) || true
    printf '%s\n' "$out" | strip_ansi | awk 'NR==1{print $2}'
}

# --- assertions ------------------------------------------------------------

assert_eq() {
    local desc=$1 expect=$2 actual=$3
    if [ "$expect" = "$actual" ]; then
        printf "    [ok] %s\n" "$desc"
        return 0
    else
        printf "    [FAIL] %s\n" "$desc"
        printf "           expected: %q\n" "$expect"
        printf "           actual:   %q\n" "$actual"
        return 1
    fi
}

assert_contains() {
    local desc=$1 needle=$2 haystack=$3
    if [[ "$haystack" == *"$needle"* ]]; then
        printf "    [ok] %s\n" "$desc"
        return 0
    else
        printf "    [FAIL] %s (looking for %q)\n" "$desc" "$needle"
        printf "           haystack: %q\n" "$haystack"
        return 1
    fi
}

assert_file() {
    local desc=$1 cid=$2 path=$3
    if docker exec "$cid" /build/bin/busybox/test -f "$path" 2>/dev/null; then
        printf "    [ok] %s\n" "$desc"
        return 0
    else
        printf "    [FAIL] %s (file missing: %s)\n" "$desc" "$path"
        return 1
    fi
}

assert_no_file() {
    local desc=$1 cid=$2 path=$3
    if ! docker exec "$cid" /build/bin/busybox/test -f "$path" 2>/dev/null; then
        printf "    [ok] %s\n" "$desc"
        return 0
    else
        printf "    [FAIL] %s (file should not exist: %s)\n" "$desc" "$path"
        return 1
    fi
}
