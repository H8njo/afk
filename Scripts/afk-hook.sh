#!/bin/bash
# AFK Hook - reads Claude Code hook JSON from stdin
# Writes session state to ~/.afk/sessions/{session_id}.json

set -euo pipefail

STATE="$1"  # working | waiting_for_user | idle
SESSION_DIR="$HOME/.afk/sessions"
mkdir -p "$SESSION_DIR"

# Read session_id from stdin JSON
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id','default'))" 2>/dev/null || echo "default")

# Write state file atomically (write to temp, then move)
TMPFILE=$(mktemp "$SESSION_DIR/.tmp.XXXXXX")
cat > "$TMPFILE" << EOF
{"state":"$STATE","session_id":"$SESSION_ID","ts":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
EOF
mv "$TMPFILE" "$SESSION_DIR/$SESSION_ID.json"
