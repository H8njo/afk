#!/bin/bash
# AFK Hook - reads Claude Code hook JSON from stdin
# Writes session state to ~/.afk/sessions/{session_id}.json

set -euo pipefail

STATE="$1"
SESSION_DIR="$HOME/.afk/sessions"
mkdir -p "$SESSION_DIR"

INPUT=$(cat)

PARSED=$(AFK_INPUT="$INPUT" python3 -c "
import os, json

d = json.loads(os.environ['AFK_INPUT'])
sid = d.get('session_id', 'default')
prompt = ''

# 1) Direct prompt field (UserPromptSubmit)
for key in ('prompt', 'message', 'input', 'content', 'text', 'query'):
    val = d.get(key, '')
    if isinstance(val, str) and val.strip():
        prompt = val.strip()
        break

# 2) Fallback: last user message from transcript
if not prompt:
    tp = d.get('transcript_path', '')
    if tp and os.path.exists(tp):
        try:
            with open(tp) as f:
                for line in f:
                    try:
                        e = json.loads(line.strip())
                        if e.get('type') == 'user':
                            msg = e.get('message', {})
                            if isinstance(msg, dict):
                                c = msg.get('content', '')
                                if isinstance(c, str) and c.strip():
                                    prompt = c.strip()
                                elif isinstance(c, list):
                                    for b in c:
                                        if isinstance(b, dict) and b.get('type') == 'text':
                                            t = b.get('text', '').strip()
                                            if t:
                                                prompt = t
                    except:
                        pass
        except:
            pass

# First line only, max 80 chars
prompt = prompt.split(chr(10))[0].strip()[:80]
print(sid)
print(prompt)
" 2>/dev/null || echo -e "default\n")

# Detect app: IDE-specific env vars take priority over TERM_PROGRAM
APP_NAME=""
if [ -n "${CURSOR_CLI:-}" ]; then
    APP_NAME="Cursor"
elif [ -n "${VSCODE_PID:-}" ]; then
    APP_NAME="VS Code"
fi

if [ -z "$APP_NAME" ]; then
    case "${TERM_PROGRAM:-}" in
        Apple_Terminal) APP_NAME="Terminal" ;;
        iTerm.app)     APP_NAME="iTerm" ;;
        vscode)        APP_NAME="VS Code" ;;
        tmux)          APP_NAME="tmux" ;;
        WarpTerminal)  APP_NAME="Warp" ;;
    esac
fi

SESSION_ID=$(echo "$PARSED" | head -1)
PROMPT=$(echo "$PARSED" | sed -n '2p')

# On non-working states, preserve existing prompt/app if new ones are empty
if [ "$STATE" != "working" ] && [ -f "$SESSION_DIR/$SESSION_ID.json" ]; then
    EXISTING=$(python3 -c "
import json
try:
    d = json.load(open('$SESSION_DIR/$SESSION_ID.json'))
    print(d.get('prompt',''))
    print(d.get('app',''))
except:
    print('')
    print('')
" 2>/dev/null || echo -e "\n")
    [ -z "$PROMPT" ] && PROMPT=$(echo "$EXISTING" | head -1)
    [ -z "$APP_NAME" ] && APP_NAME=$(echo "$EXISTING" | sed -n '2p')
fi

# Write atomically via python for safe JSON encoding
TMPFILE=$(mktemp "$SESSION_DIR/.tmp.XXXXXX")
AFK_STATE="$STATE" AFK_SID="$SESSION_ID" AFK_PROMPT="$PROMPT" AFK_APP="$APP_NAME" AFK_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)" AFK_TMP="$TMPFILE" python3 -c "
import os, json
json.dump({
    'state': os.environ['AFK_STATE'],
    'session_id': os.environ['AFK_SID'],
    'prompt': os.environ['AFK_PROMPT'],
    'app': os.environ['AFK_APP'],
    'ts': os.environ['AFK_TS']
}, open(os.environ['AFK_TMP'], 'w'), ensure_ascii=False)
" 2>/dev/null || printf '{"state":"%s","session_id":"%s","prompt":"","app":"","ts":"%s"}' \
    "$STATE" "$SESSION_ID" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$TMPFILE"
mv "$TMPFILE" "$SESSION_DIR/$SESSION_ID.json"
