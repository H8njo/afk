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

SESSION_ID=$(echo "$PARSED" | head -1)
PROMPT=$(echo "$PARSED" | sed -n '2p')

# On non-working states, preserve existing prompt if new one is empty
if [ "$STATE" != "working" ] && [ -z "$PROMPT" ] && [ -f "$SESSION_DIR/$SESSION_ID.json" ]; then
    PROMPT=$(python3 -c "
import json
try:
    print(json.load(open('$SESSION_DIR/$SESSION_ID.json')).get('prompt',''))
except:
    print('')
" 2>/dev/null || echo "")
fi

# Write atomically via python for safe JSON encoding
TMPFILE=$(mktemp "$SESSION_DIR/.tmp.XXXXXX")
AFK_STATE="$STATE" AFK_SID="$SESSION_ID" AFK_PROMPT="$PROMPT" AFK_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)" AFK_TMP="$TMPFILE" python3 -c "
import os, json
json.dump({
    'state': os.environ['AFK_STATE'],
    'session_id': os.environ['AFK_SID'],
    'prompt': os.environ['AFK_PROMPT'],
    'ts': os.environ['AFK_TS']
}, open(os.environ['AFK_TMP'], 'w'), ensure_ascii=False)
" 2>/dev/null || printf '{"state":"%s","session_id":"%s","prompt":"","ts":"%s"}' \
    "$STATE" "$SESSION_ID" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$TMPFILE"
mv "$TMPFILE" "$SESSION_DIR/$SESSION_ID.json"
