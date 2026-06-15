import Foundation

struct HookInstaller {
    private static let afkBinDir = NSHomeDirectory() + "/.afk/bin"
    private static let hookScriptPath = NSHomeDirectory() + "/.afk/bin/afk-hook.sh"
    private static let claudeSettingsPath = NSHomeDirectory() + "/.claude/settings.json"
    private static let markerComment = "afk-hook"

    static func isInstalled() -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: hookScriptPath) else { return false }
        guard fm.fileExists(atPath: claudeSettingsPath),
              let data = fm.contents(atPath: claudeSettingsPath),
              let content = String(data: data, encoding: .utf8) else {
            return false
        }
        return content.contains("afk-hook.sh")
    }

    static func install() throws {
        try installScript()
        try installHooks()
    }

    static func uninstall() throws {
        try removeHooks()
        let fm = FileManager.default
        try? fm.removeItem(atPath: hookScriptPath)
    }

    // MARK: - Script Installation

    private static func installScript() throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: afkBinDir, withIntermediateDirectories: true)

        // Read from bundled script in Resources, otherwise use embedded fallback
        let bundledPath = Bundle.main.path(forResource: "afk-hook", ofType: "sh")
        if let bundledPath = bundledPath, let bundledContent = fm.contents(atPath: bundledPath) {
            try bundledContent.write(to: URL(fileURLWithPath: hookScriptPath))
        } else {
            try Self.embeddedHookScript.write(toFile: hookScriptPath, atomically: true, encoding: .utf8)
        }

        // Make executable
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookScriptPath)
    }

    // MARK: - Hook Registration

    private static func installHooks() throws {
        let fm = FileManager.default
        let settingsDir = (claudeSettingsPath as NSString).deletingLastPathComponent
        try fm.createDirectory(atPath: settingsDir, withIntermediateDirectories: true)

        var settings: [String: Any] = [:]
        if let data = fm.contents(atPath: claudeSettingsPath),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = existing
        }

        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        let hookScript = "~/.afk/bin/afk-hook.sh"

        let hookEvents: [(String, String)] = [
            ("UserPromptSubmit", "working"),
            ("Notification", "waiting_for_user"),
            ("Stop", "idle"),
        ]

        for (event, state) in hookEvents {
            var eventHooks = hooks[event] as? [[String: Any]] ?? []

            // Check if AFK hook already exists
            let alreadyExists = eventHooks.contains { hookEntry in
                if let matcherHooks = hookEntry["hooks"] as? [[String: Any]] {
                    return matcherHooks.contains { h in
                        (h["command"] as? String)?.contains("afk-hook.sh") == true
                    }
                }
                return false
            }

            if !alreadyExists {
                let hookEntry: [String: Any] = [
                    "hooks": [
                        [
                            "type": "command",
                            "command": "\(hookScript) \(state)",
                            "timeout": 5,
                        ] as [String: Any]
                    ]
                ]
                eventHooks.append(hookEntry)
            }

            hooks[event] = eventHooks
        }

        settings["hooks"] = hooks

        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: claudeSettingsPath))
    }

    // MARK: - Embedded Script

    private static let embeddedHookScript = """
#!/bin/bash
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

for key in ('prompt', 'message', 'input', 'content', 'text', 'query'):
    val = d.get(key, '')
    if isinstance(val, str) and val.strip():
        prompt = val.strip()
        break

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

prompt = prompt.split(chr(10))[0].strip()[:80]
print(sid)
print(prompt)
" 2>/dev/null || echo -e "default\\n")

SESSION_ID=$(echo "$PARSED" | head -1)
PROMPT=$(echo "$PARSED" | sed -n '2p')

if [ "$STATE" != "working" ] && [ -z "$PROMPT" ] && [ -f "$SESSION_DIR/$SESSION_ID.json" ]; then
    PROMPT=$(python3 -c "
import json
try:
    print(json.load(open('$SESSION_DIR/$SESSION_ID.json')).get('prompt',''))
except:
    print('')
" 2>/dev/null || echo "")
fi

TMPFILE=$(mktemp "$SESSION_DIR/.tmp.XXXXXX")
AFK_STATE="$STATE" AFK_SID="$SESSION_ID" AFK_PROMPT="$PROMPT" AFK_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)" AFK_TMP="$TMPFILE" python3 -c "
import os, json
json.dump({
    'state': os.environ['AFK_STATE'],
    'session_id': os.environ['AFK_SID'],
    'prompt': os.environ['AFK_PROMPT'],
    'ts': os.environ['AFK_TS']
}, open(os.environ['AFK_TMP'], 'w'), ensure_ascii=False)
" 2>/dev/null || printf '{"state":"%s","session_id":"%s","prompt":"","ts":"%s"}' \\
    "$STATE" "$SESSION_ID" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$TMPFILE"
mv "$TMPFILE" "$SESSION_DIR/$SESSION_ID.json"
"""

    // MARK: - Hook Removal

    private static func removeHooks() throws {
        let fm = FileManager.default
        guard let data = fm.contents(atPath: claudeSettingsPath),
              var settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = settings["hooks"] as? [String: Any] else {
            return
        }

        for event in ["UserPromptSubmit", "Notification", "Stop"] {
            if var eventHooks = hooks[event] as? [[String: Any]] {
                eventHooks.removeAll { hookEntry in
                    if let matcherHooks = hookEntry["hooks"] as? [[String: Any]] {
                        return matcherHooks.contains { h in
                            (h["command"] as? String)?.contains("afk-hook.sh") == true
                        }
                    }
                    return false
                }
                if eventHooks.isEmpty {
                    hooks.removeValue(forKey: event)
                } else {
                    hooks[event] = eventHooks
                }
            }
        }

        settings["hooks"] = hooks
        let newData = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try newData.write(to: URL(fileURLWithPath: claudeSettingsPath))
    }
}
