import SwiftUI
import Combine

@MainActor
class AppState: ObservableObject {
    enum AIState: String, Codable {
        case idle
        case working
        case waitingForUser = "waiting_for_user"
    }

    enum CompletionMode: String, CaseIterable {
        case notify = "notify"
        case autoSwitch = "auto_switch"

        var label: String {
            switch self {
            case .notify: return "Notification"
            case .autoSwitch: return "Auto Switch"
            }
        }
    }

    @AppStorage("breakAppBundleID") var breakAppBundleID: String = "com.apple.Safari"
    @AppStorage("sourceAppBundleID") var sourceAppBundleID: String = AppSwitcher.autoSourceID
    @AppStorage("completionMode") var completionMode: String = CompletionMode.notify.rawValue
    @AppStorage("switchDelay") var switchDelay: Double = 2.0
    @AppStorage("notificationSound") var notificationSound: String = "Ping"
    @AppStorage("notificationDuration") var notificationDuration: Double = 8.0
    @AppStorage("isPaused") var isPaused: Bool = false

    @Published var currentState: AIState = .idle
    @Published var isHookInstalled: Bool = false
    @Published var sessions: [SessionInfo] = []

    private var sessionMonitor: SessionMonitor?
    private var appSwitcher = AppSwitcher()

    var menuBarIcon: String {
        if isPaused { return "pause.circle" }
        switch currentState {
        case .idle: return "circle"
        case .working: return "circle.fill"
        case .waitingForUser: return "exclamationmark.circle.fill"
        }
    }

    var statusText: String {
        if isPaused { return "Paused" }
        switch currentState {
        case .idle: return "Idle"
        case .working: return "AI Working..."
        case .waitingForUser: return "AI Needs You!"
        }
    }

    private let notificationManager = NotificationManager.shared

    init() {
        checkHookInstalled()
        startMonitoring()
    }

    func startMonitoring() {
        sessionMonitor = SessionMonitor { [weak self] newState, sessions in
            Task { @MainActor in
                self?.sessions = sessions
                self?.handleStateChange(newState)
            }
        }
        sessionMonitor?.start()
    }

    private func handleStateChange(_ newState: AIState) {
        let oldState = currentState
        currentState = newState

        guard !isPaused else { return }
        guard oldState != newState else { return }

        Self.log("state \(oldState.rawValue) → \(newState.rawValue), mode=\(completionMode)")

        switch newState {
        case .working:
            appSwitcher.switchToBreakApp(bundleID: breakAppBundleID, delay: switchDelay)
        case .waitingForUser:
            if completionMode == CompletionMode.notify.rawValue {
                let done = sessions.filter { $0.state == .waitingForUser }
                Self.log("notify waitingForUser count=\(done.count)")
                for session in done {
                    notificationManager.notify(session: session)
                }
            } else {
                appSwitcher.switchToSourceApp(bundleID: resolveSourceApp())
            }
        case .idle:
            if oldState == .working || oldState == .waitingForUser {
                if completionMode == CompletionMode.notify.rawValue {
                    let done = sessions.filter { $0.state != .working }
                    Self.log("notify idle count=\(done.count)")
                    for session in done {
                        notificationManager.notify(session: session)
                    }
                } else {
                    appSwitcher.switchToSourceApp(bundleID: resolveSourceApp())
                }
            }
        }
    }

    private func resolveSourceApp() -> String {
        guard sourceAppBundleID == AppSwitcher.autoSourceID else {
            return sourceAppBundleID
        }
        let target = sessions.first(where: { $0.state == .waitingForUser })
            ?? sessions.first
        if let bundleID = target?.resolveBundleID() {
            return bundleID
        }
        return "com.apple.Terminal"
    }

    func refreshSessions() {
        sessionMonitor?.refresh()
    }

    static func log(_ msg: String) {
        let line = "\(Date()): \(msg)\n"
        let path = NSHomeDirectory() + "/.afk/debug.log"
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        } else {
            try? line.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    func checkHookInstalled() {
        isHookInstalled = HookInstaller.isInstalled()
    }
}
