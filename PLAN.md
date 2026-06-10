# AFK v1 Implementation Plan

## Context

AFK는 AI 코딩 도구(Claude Code)의 작업 상태를 감지해서 자동으로 앱을 전환하는 macOS 네이티브 메뉴바 앱이다. AI에 요청을 보내면 지정한 "break 앱"(유튜브 등)을 자동 포커스하고, AI가 끝나면 다시 AI 앱(터미널 등)으로 복귀한다.

디자인 문서: `DESIGN.md`

## v1 Scope

**IN:**
- Claude Code hook 스크립트 (stdin JSON → 세션별 상태 파일)
- FSEvents 기반 상태 모니터
- NSRunningApplication 기반 앱 전환 (2초 딜레이 기본)
- SwiftUI MenuBarExtra (상태 아이콘 + 드롭다운)
- SwiftUI Settings 창 (break 앱 선택, source 앱 선택, 딜레이)
- 첫 실행 시 Claude Code hook 자동 등록

**NOT in scope (v2):**
- Dashboard/통계
- 크로스 디바이스 (iPhone)
- Task-aware break routing (작업 시간 예측)
- Progressive interruption "점진적" 모드
- Cursor/VSCode 지원
- Mac App Store 배포

## Architecture

```
┌─────────────────────────────────────────┐
│           AFK Menu Bar App              │
│         (Swift + SwiftUI)               │
│                                         │
│  ┌─────────────┐  ┌─────────────────┐  │
│  │ SessionMgr  │  │  AppSwitcher    │  │
│  │             │  │                 │  │
│  │ FSEvents    │  │ NSRunning       │  │
│  │ watcher on  │──│ Application     │  │
│  │ ~/.afk/     │  │ .activate()     │  │
│  │ sessions/   │  │                 │  │
│  └─────────────┘  └─────────────────┘  │
│         ↑              ↑               │
│  ┌─────────────┐  ┌─────────────────┐  │
│  │ MenuBar     │  │ Settings        │  │
│  │ (status     │  │ (break app,     │  │
│  │  icon +     │  │  source app,    │  │
│  │  dropdown)  │  │  delay)         │  │
│  └─────────────┘  └─────────────────┘  │
└─────────────────────────────────────────┘
         ↑
┌─────────────────┐
│  afk-hook.sh    │  Claude Code hook
│                 │  stdin JSON → parse session_id
│  writes to:     │  → ~/.afk/sessions/{id}.json
└─────────────────┘
```

## State Flow

```
Claude Code hook events → stdin JSON → afk-hook.sh
    │
    ├─ UserPromptSubmit → writes {"state":"working"} → FSEvents fires
    │                                                    → 2s delay
    │                                                    → focus break app
    │
    ├─ Notification     → writes {"state":"waiting"}  → FSEvents fires
    │                                                    → immediately
    │                                                    → focus source app
    │
    └─ Stop             → writes {"state":"idle"}     → FSEvents fires
                                                         → immediately
                                                         → focus source app
```

## Implementation Steps

### Step 1: Xcode Project + MenuBarExtra Shell

**File: `AFK/AFKApp.swift`**
```swift
@main
struct AFKApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            Image(systemName: appState.menuBarIcon)
        }

        Settings {
            SettingsView(appState: appState)
        }
    }
}
```

- macOS 13.0+ deployment target
- App Sandbox OFF (Accessibility 권한 + 파일 시스템 접근 필요)
- LSUIElement = YES (Dock 아이콘 숨김, 메뉴바만)

### Step 2: AppState Model

**File: `AFK/Models/AppState.swift`**

```swift
@MainActor
class AppState: ObservableObject {
    enum AIState: String, Codable {
        case idle, working, waitingForUser = "waiting_for_user"
    }

    @Published var currentState: AIState = .idle
    @Published var isPaused: Bool = false
    @Published var breakAppBundleID: String = ""  // e.g. "com.apple.Safari"
    @Published var sourceAppBundleID: String = ""  // e.g. "com.apple.Terminal"
    @Published var switchDelay: Double = 2.0       // seconds
    @Published var isHookInstalled: Bool = false

    var menuBarIcon: String {
        if isPaused { return "pause.circle" }
        switch currentState {
        case .idle: return "circle"
        case .working: return "circle.fill"           // green
        case .waitingForUser: return "exclamationmark.circle.fill"  // red
        }
    }
}
```

설정은 `@AppStorage` (UserDefaults 래퍼)로 자동 영속화.

### Step 3: Hook Script

**File: `Scripts/afk-hook.sh`**

```bash
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
# SESSION_ID already has fallback from python3 line above

# Write state file atomically (write to temp, then move)
TMPFILE=$(mktemp "$SESSION_DIR/.tmp.XXXXXX")
cat > "$TMPFILE" << EOF
{"state":"$STATE","session_id":"$SESSION_ID","ts":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
EOF
mv "$TMPFILE" "$SESSION_DIR/$SESSION_ID.json"
```

**Hook 등록 (settings.json에 추가):**

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [{
          "type": "command",
          "command": "echo working | ~/.afk/bin/afk-hook.sh working",
          "timeout": 5
        }]
      }
    ],
    "Notification": [
      {
        "hooks": [{
          "type": "command",
          "command": "~/.afk/bin/afk-hook.sh waiting_for_user",
          "timeout": 5
        }]
      }
    ],
    "Stop": [
      {
        "hooks": [{
          "type": "command",
          "command": "~/.afk/bin/afk-hook.sh idle",
          "timeout": 5
        }]
      }
    ]
  }
}
```

주의: hooks는 stdin으로 JSON을 받으므로 스크립트에서 cat으로 읽음. command 필드에서 파이프 사용 불가 시 스크립트 내부에서 처리.

### Step 4: SessionMonitor (FSEvents)

**File: `AFK/Services/SessionMonitor.swift`**

```swift
class SessionMonitor {
    private var stream: FSEventStreamRef?
    private let sessionsPath: String  // ~/.afk/sessions/
    private let onChange: (AppState.AIState, String) -> Void

    // FSEvents callback → read changed files → parse JSON → call onChange
    // Aggregate state: if ANY session is "waiting_for_user" → switch to source app
    // If ALL sessions are "working" → switch to break app
    // If ALL sessions are "idle" → do nothing (stay on current app)
}
```

FSEvents 콜백에서:
1. `~/.afk/sessions/` 디렉토리의 모든 .json 파일 읽기
2. 각 세션 상태 aggregate
3. 하나라도 `waiting_for_user` → 즉시 source 앱 포커스
4. 모두 `working` → 딜레이 후 break 앱 포커스
5. 모두 `idle` → 상태만 업데이트, 앱 전환 안 함

### Step 5: AppSwitcher

**File: `AFK/Services/AppSwitcher.swift`**

```swift
class AppSwitcher {
    private var pendingSwitch: DispatchWorkItem?

    func switchToBreakApp(bundleID: String, delay: TimeInterval) {
        pendingSwitch?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.activateApp(bundleID: bundleID)
        }
        pendingSwitch = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func switchToSourceApp(bundleID: String) {
        pendingSwitch?.cancel()  // cancel pending break app switch
        activateApp(bundleID: bundleID)
    }

    private func activateApp(bundleID: String) {
        guard let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .first else {
            // App not running → launch it
            NSWorkspace.shared.launchApplication(
                withBundleIdentifier: bundleID,
                additionalEventParamDescriptor: nil,
                launchIdentifier: nil
            )
            return
        }
        app.activate(options: .activateIgnoringOtherApps)
    }
}
```

핵심: `pendingSwitch?.cancel()`로 빠른 응답 시 전환 취소 (thrash 방지).

### Step 6: SettingsView

**File: `AFK/Views/SettingsView.swift`**

```swift
struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var installedApps: [InstalledApp] = []

    var body: some View {
        Form {
            // Break App picker (NSWorkspace.shared.runningApplications로 목록)
            Picker("Break App", selection: $appState.breakAppBundleID) { ... }

            // Source App picker
            Picker("Source App (AI tool)", selection: $appState.sourceAppBundleID) { ... }

            // Delay slider
            Slider(value: $appState.switchDelay, in: 0...10, step: 0.5)

            // Hook status + install button
            Section("Claude Code Hook") {
                if appState.isHookInstalled {
                    Label("Installed", systemImage: "checkmark.circle.fill")
                } else {
                    Button("Install Hook") { installHook() }
                }
            }

            // Accessibility permission check
            Section("Permissions") {
                if AXIsProcessTrusted() {
                    Label("Accessibility Granted", systemImage: "checkmark.circle.fill")
                } else {
                    Button("Grant Accessibility") {
                        let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
                        AXIsProcessTrustedWithOptions(opts as CFDictionary)
                    }
                }
            }
        }
        .frame(width: 400, height: 350)
    }
}
```

### Step 7: MenuBarView

**File: `AFK/Views/MenuBarView.swift`**

```swift
struct MenuBarView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack {
            Text(statusText).font(.headline)
            Divider()
            Toggle("Pause", isOn: $appState.isPaused)
            Divider()
            SettingsLink { Text("Settings...") }
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }

    var statusText: String {
        if appState.isPaused { return "Paused" }
        switch appState.currentState {
        case .idle: return "Idle"
        case .working: return "AI Working..."
        case .waitingForUser: return "AI Needs You!"
        }
    }
}
```

### Step 8: HookInstaller

**File: `AFK/Services/HookInstaller.swift`**

기존 `~/.claude/settings.json`을 읽고, hooks 프로퍼티에 AFK hooks를 추가 (기존 hooks와 merge). 이미 존재하면 skip. `afk-hook.sh`를 `~/.afk/bin/`에 복사.

주의사항:
- 기존 settings.json의 다른 설정을 보존
- hooks 내 같은 이벤트에 이미 다른 hook이 있으면 배열에 추가 (덮어쓰기 X)
- 언인스톨 기능도 제공 (hooks에서 AFK 항목만 제거)

## File Structure (v1)

```
AFK/
├── Package.swift
├── Sources/AFK/
│   ├── AFKApp.swift                 # @main, MenuBarExtra scene
│   ├── Models/
│   │   └── AppState.swift           # State enum + settings (@Published)
│   ├── Services/
│   │   ├── SessionMonitor.swift     # FSEvents watcher
│   │   ├── AppSwitcher.swift        # NSRunningApplication focus
│   │   └── HookInstaller.swift      # Claude Code hook setup
│   └── Views/
│       ├── MenuBarView.swift        # Status dropdown
│       └── SettingsView.swift       # Settings window
├── Scripts/
│   ├── afk-hook.sh                  # Hook script (copied to ~/.afk/bin/)
│   ├── bundle.sh                    # Build + create .app bundle
│   └── test.sh                      # Test suite
├── DESIGN.md
└── PLAN.md
```

## Test Strategy

### Unit Tests
```
TEST COVERAGE
===========================
[+] AppState
    ├── [GAP] State transitions (idle→working→waiting→idle)
    ├── [GAP] menuBarIcon returns correct icon per state
    └── [GAP] isPaused blocks state transitions

[+] AppSwitcher
    ├── [GAP] switchToBreakApp calls activate after delay
    ├── [GAP] switchToSourceApp cancels pending break switch
    ├── [GAP] switchToSourceApp activates immediately
    └── [GAP] app not running → launches app

[+] SessionMonitor
    ├── [OK] Parses valid state JSON
    ├── [OK] Handles malformed JSON gracefully
    ├── [OK] Aggregates multiple sessions correctly
    │   ├── [OK] Any waiting_for_user → returns waitingForUser
    │   ├── [OK] All working → returns working
    │   └── [OK] All idle → returns idle
    └── [GAP] Handles missing/deleted session files

[+] HookInstaller
    ├── [GAP] Installs hooks to empty settings.json
    ├── [GAP] Merges hooks with existing hooks
    ├── [GAP] Detects already-installed hooks
    └── [GAP] Uninstalls only AFK hooks

[+] afk-hook.sh
    ├── [OK] Writes correct JSON for each state
    ├── [OK] Parses session_id from stdin
    ├── [OK] Handles missing session_id (defaults to "default")
    ├── [OK] Atomic write (temp file + mv)
    └── [OK] Creates sessions directory if missing

COVERAGE: 11/18 paths tested (via Scripts/test.sh)
GAPS: 7 paths need tests (require XCTest / Xcode.app)
```

### Manual Test
- Claude Code에서 요청 보내기 → break 앱 포커스 확인 (2초 딜레이)
- Claude Code 완료 → source 앱 복귀 확인 (즉시)
- Pause 토글 → 전환 안 됨 확인
- 설정 변경 후 앱 재시작 → 설정 유지 확인

## Failure Modes

| Failure | Tested | Handling | User sees |
|---------|--------|----------|-----------|
| Hook script에 stdin이 안 옴 | OK | default session_id 사용 | 정상 동작 |
| settings.json 파싱 실패 | GAP | 기존 파일 보존, 에러 로그 | 설정에서 "Install Failed" |
| Accessibility 권한 없음 | GAP | AXIsProcessTrusted 체크 → 안내 | 설정에서 "Grant" 버튼 |
| Break 앱이 설치 안 됨 | GAP | NSWorkspace.open 실패 → 무시 | 전환 안 됨 (silent) |
| sessions/ 디렉토리 삭제됨 | OK | 재생성 | 정상 동작 |
| 동시에 여러 세션 write | OK | 세션별 파일 분리 | 정상 동작 |

## Eng Review Decisions

1. **Hook stdin 파싱** → python3 -c (macOS 기본 포함, JSON edge case 안전)
2. **Hook 등록** → settings.json merge (마커 기반 추가/제거, 기존 hooks 보존)
3. **Accessibility** → 첫 실행 시 AXIsProcessTrusted 체크 → 없으면 Settings 자동 오픈 + 시스템 권한 요청
4. **AppState 구조** → 단일 클래스 유지 + @AppStorage로 설정 영속화 (v1 규모에 적합)
5. **테스트** → Shell 기반 test.sh (XCTest는 Xcode.app 필요)
6. **FSEvents latency** → DispatchSource로 즉시 반응, 스테일 세션 5분 후 자동 정리

## Verification

```bash
# 1. Build
swift build -c release

# 2. Bundle into .app
bash Scripts/bundle.sh

# 3. Hook script test
bash Scripts/test.sh

# 4. Manual integration test
# - open .build/AFK.app
# - Settings에서 break app = Safari, source app = Terminal 설정
# - Terminal에서 Claude Code 실행
# - 요청 보내기 → Safari 포커스 확인 (2초 후)
# - Claude 완료 → Terminal 복귀 확인
```
