#!/bin/bash
# AFK Test Suite - tests hook script and session file logic
set -euo pipefail

PASS=0
FAIL=0
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

pass() { ((PASS++)); echo "  PASS: $1"; }
fail() { ((FAIL++)); echo "  FAIL: $1 — $2"; }

run_hook() {
    local state="$1"
    local stdin_json="$2"
    local session_dir="$3"
    echo "$stdin_json" | SESSION_DIR="$session_dir" bash -c '
        set -euo pipefail
        STATE="'"$state"'"
        SESSION_DIR="'"$session_dir"'"
        mkdir -p "$SESSION_DIR"
        INPUT=$(cat)
        SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get(\"session_id\",\"default\"))" 2>/dev/null || echo "default")
        TMPFILE=$(mktemp "$SESSION_DIR/.tmp.XXXXXX")
        printf "{\"state\":\"%s\",\"session_id\":\"%s\",\"ts\":\"%s\"}" "$STATE" "$SESSION_ID" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$TMPFILE"
        mv "$TMPFILE" "$SESSION_DIR/$SESSION_ID.json"
    '
}

echo "=== Hook Script Tests ==="

# Test 1: Working state
SD="$TEST_DIR/t1"; mkdir -p "$SD"
run_hook "working" '{"session_id":"s1"}' "$SD"
STATE=$(python3 -c "import json; print(json.load(open('$SD/s1.json'))['state'])")
[ "$STATE" = "working" ] && pass "writes working state" || fail "writes working state" "got $STATE"

# Test 2: Waiting for user state
SD="$TEST_DIR/t2"; mkdir -p "$SD"
run_hook "waiting_for_user" '{"session_id":"s2"}' "$SD"
STATE=$(python3 -c "import json; print(json.load(open('$SD/s2.json'))['state'])")
[ "$STATE" = "waiting_for_user" ] && pass "writes waiting_for_user state" || fail "writes waiting_for_user state" "got $STATE"

# Test 3: Idle state
SD="$TEST_DIR/t3"; mkdir -p "$SD"
run_hook "idle" '{"session_id":"s3"}' "$SD"
STATE=$(python3 -c "import json; print(json.load(open('$SD/s3.json'))['state'])")
[ "$STATE" = "idle" ] && pass "writes idle state" || fail "writes idle state" "got $STATE"

# Test 4: Parses session_id from stdin
SD="$TEST_DIR/t4"; mkdir -p "$SD"
run_hook "working" '{"session_id":"myid123"}' "$SD"
[ -f "$SD/myid123.json" ] && pass "parses session_id from stdin" || fail "parses session_id from stdin" "file not found"

# Test 5: Default session_id when missing
SD="$TEST_DIR/t5"; mkdir -p "$SD"
run_hook "working" '{}' "$SD"
[ -f "$SD/default.json" ] && pass "defaults to 'default' session_id" || fail "defaults to 'default' session_id" "file not found"

# Test 6: Default session_id on invalid JSON
SD="$TEST_DIR/t6"; mkdir -p "$SD"
run_hook "working" 'not json at all' "$SD"
[ -f "$SD/default.json" ] && pass "defaults on invalid JSON" || fail "defaults on invalid JSON" "file not found"

# Test 7: Atomic write (no partial files)
SD="$TEST_DIR/t7"; mkdir -p "$SD"
run_hook "working" '{"session_id":"atomic"}' "$SD"
TMPCOUNT=$(find "$SD" -name '.tmp.*' 2>/dev/null | wc -l | tr -d ' ')
[ "$TMPCOUNT" = "0" ] && pass "no temp files left (atomic write)" || fail "no temp files left" "found $TMPCOUNT"

# Test 8: Valid JSON output
SD="$TEST_DIR/t8"; mkdir -p "$SD"
run_hook "working" '{"session_id":"valid"}' "$SD"
python3 -c "import json; json.load(open('$SD/valid.json'))" 2>/dev/null && pass "produces valid JSON" || fail "produces valid JSON" "parse error"

# Test 9: Has timestamp
SD="$TEST_DIR/t9"; mkdir -p "$SD"
run_hook "working" '{"session_id":"ts"}' "$SD"
TS=$(python3 -c "import json; print(json.load(open('$SD/ts.json'))['ts'])")
[ -n "$TS" ] && pass "includes timestamp" || fail "includes timestamp" "empty ts"

# Test 10: Creates sessions directory
SD="$TEST_DIR/t10/nested"
run_hook "working" '{"session_id":"dir"}' "$SD"
[ -d "$SD" ] && pass "creates session directory" || fail "creates session directory" "dir not created"

# Test 11: Overwrites existing state
SD="$TEST_DIR/t11"; mkdir -p "$SD"
run_hook "working" '{"session_id":"overwrite"}' "$SD"
run_hook "idle" '{"session_id":"overwrite"}' "$SD"
STATE=$(python3 -c "import json; print(json.load(open('$SD/overwrite.json'))['state'])")
[ "$STATE" = "idle" ] && pass "overwrites existing state" || fail "overwrites existing state" "got $STATE"

echo ""
echo "=== Aggregation Logic Tests ==="

# Simulate aggregation logic in bash
aggregate() {
    local dir="$1"
    local has_waiting=false
    local has_working=false
    local count=0
    for f in "$dir"/*.json; do
        [ -f "$f" ] || continue
        ((count++))
        state=$(python3 -c "import json; print(json.load(open('$f'))['state'])")
        [ "$state" = "waiting_for_user" ] && has_waiting=true
        [ "$state" = "working" ] && has_working=true
    done
    [ $count -eq 0 ] && echo "idle" && return
    $has_waiting && echo "waiting_for_user" && return
    $has_working && echo "working" && return
    echo "idle"
}

# Test 12: Empty dir → idle
SD="$TEST_DIR/a1"; mkdir -p "$SD"
touch "$SD/.keep"  # ensure dir exists but no json
RESULT=$(aggregate "$SD")
[ "$RESULT" = "idle" ] && pass "empty → idle" || fail "empty → idle" "got $RESULT"

# Test 13: All working → working
SD="$TEST_DIR/a2"; mkdir -p "$SD"
printf '{"state":"working","session_id":"a","ts":"now"}' > "$SD/a.json"
printf '{"state":"working","session_id":"b","ts":"now"}' > "$SD/b.json"
RESULT=$(aggregate "$SD")
[ "$RESULT" = "working" ] && pass "all working → working" || fail "all working → working" "got $RESULT"

# Test 14: Any waiting → waiting_for_user
SD="$TEST_DIR/a3"; mkdir -p "$SD"
printf '{"state":"working","session_id":"a","ts":"now"}' > "$SD/a.json"
printf '{"state":"waiting_for_user","session_id":"b","ts":"now"}' > "$SD/b.json"
RESULT=$(aggregate "$SD")
[ "$RESULT" = "waiting_for_user" ] && pass "any waiting → waiting_for_user" || fail "any waiting → waiting_for_user" "got $RESULT"

# Test 15: All idle → idle
SD="$TEST_DIR/a4"; mkdir -p "$SD"
printf '{"state":"idle","session_id":"a","ts":"now"}' > "$SD/a.json"
printf '{"state":"idle","session_id":"b","ts":"now"}' > "$SD/b.json"
RESULT=$(aggregate "$SD")
[ "$RESULT" = "idle" ] && pass "all idle → idle" || fail "all idle → idle" "got $RESULT"

# Test 16: Mixed working+idle → working
SD="$TEST_DIR/a5"; mkdir -p "$SD"
printf '{"state":"working","session_id":"a","ts":"now"}' > "$SD/a.json"
printf '{"state":"idle","session_id":"b","ts":"now"}' > "$SD/b.json"
RESULT=$(aggregate "$SD")
[ "$RESULT" = "working" ] && pass "mixed working+idle → working" || fail "mixed working+idle → working" "got $RESULT"

echo ""
echo "================================"
echo "Results: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit $FAIL
