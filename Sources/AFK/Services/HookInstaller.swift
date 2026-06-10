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

        let script = """
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
        """

        // Read from bundled script if available, otherwise use embedded
        let bundledPath = Bundle.main.path(forResource: "afk-hook", ofType: "sh")
        if let bundledPath = bundledPath, let bundledContent = fm.contents(atPath: bundledPath) {
            try bundledContent.write(to: URL(fileURLWithPath: hookScriptPath))
        } else {
            try script.write(toFile: hookScriptPath, atomically: true, encoding: .utf8)
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
