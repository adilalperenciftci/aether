# Process and port helpers shared by test_http_reverse_proxy_pool.sh and
# test_http_reverse_proxy_pool_extra.sh. Sourced once TMPDIR, PIDS,
# PROXY_PID, $TMPDIR/server and tests/lib/server_jobs.sh are in place.
#
# Every role binds a port the kernel picks and prints `READY <port>`
# (#2812): fixed ports 19100-19103 let two sweeps on one machine (two
# checkouts, or the parallel agents that work this repository) answer each
# other's requests. These helpers read each role's port and publish:
#   UP_A UP_B UP_C   the upstreams' URLs, exported for the proxy roles and
#                    used as the labels of the proxy's /proxy-metrics
#   UP_B_ADMIN       upstream B itself, for its /admin toggles
#   PROXY            the current subtest's proxy

start_proc() {
    role="$1"
    log="$TMPDIR/$role.log"
    "$TMPDIR/server" "$role" >"$log" 2>&1 &
    new_pid=$!
    eval "PID_$role=\$new_pid"
}

# Waits until `role` has printed `READY <port>` and answers on that port,
# then sets ROLE_PORT. A role that dies, or does not answer within 15 s,
# fails the test with its log, so a failure explains itself instead of
# producing "(no output)".
wait_for_role() {
    role="$1"
    log="$TMPDIR/$role.log"
    pid=$(eval echo \$PID_$role)
    ROLE_PORT=""
    deadline=$(($(date +%s) + 15))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        if ! server_alive "$pid"; then
            echo "  [FAIL] $role died:"; head -30 "$log"; exit 1
        fi
        if [ -z "$ROLE_PORT" ]; then
            ROLE_PORT=$(sed -n 's/^READY \([0-9][0-9]*\).*/\1/p' "$log" 2>/dev/null | head -1)
        fi
        if [ -n "$ROLE_PORT" ] &&
           curl -s -o /dev/null --connect-timeout 0.3 --max-time 1 \
                "http://127.0.0.1:$ROLE_PORT/health" 2>/dev/null; then
            return 0
        fi
        sleep 0.1
    done
    echo "  [FAIL] $role never answered (port '${ROLE_PORT}'):"; head -30 "$log"; exit 1
}

# The three upstreams start once and stay up across every subtest.
start_three_upstreams() {
    start_proc upstream_a; PIDS="$PIDS $PID_upstream_a"
    start_proc upstream_b; PIDS="$PIDS $PID_upstream_b"
    start_proc upstream_c; PIDS="$PIDS $PID_upstream_c"
    wait_for_role upstream_a
    UP_A="http://localhost:$ROLE_PORT"
    wait_for_role upstream_b
    UP_B="http://localhost:$ROLE_PORT"
    UP_B_ADMIN="http://127.0.0.1:$ROLE_PORT"
    wait_for_role upstream_c
    UP_C="http://localhost:$ROLE_PORT"
    export UP_A UP_B UP_C
}

# A fresh proxy per subtest; the upstreams stay warm. Each proxy binds a
# port of its own, so its bind cannot lose to the previous proxy's listener
# in TIME_WAIT, which on the fixed port 19100 needed a retry loop.
start_proxy() {
    proxy_role="$1"
    start_proc "$proxy_role"
    PROXY_PID=$(eval echo \$PID_$proxy_role)
    wait_for_role "$proxy_role"
    PROXY="http://127.0.0.1:$ROLE_PORT"
}

stop_proxy() {
    if [ -n "$PROXY_PID" ]; then
        kill_server "$PROXY_PID"
        PROXY_PID=""
    fi
}

# Undoes a /admin/503 an earlier subtest left on upstream B. Idempotent.
clear_upstream_b_503() {
    curl -s -o /dev/null --max-time 3 -X POST "$UP_B_ADMIN/admin/200" 2>/dev/null || true
}
