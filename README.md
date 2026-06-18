# AFK

A macOS menu bar app that detects [Claude Code](https://docs.anthropic.com/en/docs/claude-code)'s working state and automatically manages app focus — so you can browse, watch, or relax while AI works, and get pulled back when it's done.

## How It Works

1. Claude Code starts working → AFK switches you to a **break app** (Safari, YouTube, etc.)
2. Claude Code finishes → AFK notifies you or switches you back to the coding app

AFK uses Claude Code's [hooks system](https://docs.anthropic.com/en/docs/claude-code/hooks) to detect state changes (`UserPromptSubmit`, `Notification`, `Stop`) and writes per-session state files to `~/.afk/sessions/`.

## Install

### Homebrew

```bash
brew tap H8njo/tap
brew install --cask afk
```

### Manual

1. Download `AFK.zip` from the [latest release](https://github.com/H8njo/afk/releases/latest)
2. Unzip and move `AFK.app` to `/Applications`
3. Run `xattr -cr /Applications/AFK.app` (required for unsigned app)
4. Open AFK

## Setup

1. **Install Hook** — Open AFK → Settings → Click "Install Hook". This registers the hook script with Claude Code's `~/.claude/settings.json`.
2. **Grant Accessibility** — Required for app switching. Settings → Permissions → Grant. After rebuilding from source, toggle OFF → ON to re-trust the new binary.

## Settings

### App Switching

| Option | Description |
|--------|-------------|
| **Switch to break app** | Enable/disable automatic switching when Claude Code starts working |
| **Break App** | The app to focus during AI work (default: Safari) |
| **On Completion** | `Notification` (floating banner) or `Auto Switch` (immediate focus switch) |
| **Source App** | When using Auto Switch — `Session App (Auto)` detects which app the session runs in |
| **Switch delay** | Delay before switching to break app (0–10s, default: 2s) |

### Notification

| Option | Description |
|--------|-------------|
| **Sound** | Notification sound (system sounds like Ping, Glass, etc.) |
| **Duration** | How long the banner stays visible (3–30s, default: 8s) |

Notification banners stack vertically when multiple sessions complete at the same time. Each banner shows the app name, prompt text, and a "Back to [App]" button.

## Multi-Session Support

AFK tracks multiple Claude Code sessions independently. Each session detects which app it's running in:

- **Cursor** — detected via `CURSOR_CLI` environment variable
- **VS Code** — detected via `VSCODE_PID` environment variable
- **Terminal / iTerm / Warp** — detected via `TERM_PROGRAM`

Sessions from killed apps are automatically cleaned up via a 5-second polling interval.

## Menu Bar

Click the menu bar icon to see:

- Active sessions with app name, prompt text, and state
- Click a session to focus its app
- **Refresh** (Cmd+R) — manually refresh session list
- **Pause** (Cmd+P) — temporarily disable all switching

Menu bar icon states:
- `○` Idle
- `●` Working
- `⚠` Needs attention
- `⏸` Paused

## Requirements

- macOS 13.0+ (Ventura)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with hooks support

## Build from Source

```bash
git clone https://github.com/H8njo/afk.git
cd afk
swift build
bash Scripts/bundle.sh
open .build/AFK.app
```

## Project Structure

```
Sources/AFK/
  AFKApp.swift              # App entry point, MenuBarExtra scene
  Models/AppState.swift     # State management, settings, completion handling
  Services/
    SessionMonitor.swift    # File watcher + poll timer for session state
    AppSwitcher.swift       # NSRunningApplication-based app focus switching
    NotificationManager.swift # Floating banner notifications
    HookInstaller.swift     # Claude Code hook registration
  Views/
    MenuBarView.swift       # Menu bar dropdown
    SettingsView.swift      # Settings window
Scripts/
  afk-hook.sh              # Hook script (reads stdin JSON, writes session files)
  bundle.sh                # Builds .app bundle
  generate-icon.swift      # Generates app icon programmatically
```

## License

MIT
