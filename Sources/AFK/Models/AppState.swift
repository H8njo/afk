import SwiftUI
import Combine

@MainActor
class AppState: ObservableObject {
    enum AIState: String, Codable {
        case idle
        case working
        case waitingForUser = "waiting_for_user"
    }

    @AppStorage("breakAppBundleID") var breakAppBundleID: String = "com.apple.Safari"
    @AppStorage("sourceAppBundleID") var sourceAppBundleID: String = "com.apple.Terminal"
    @AppStorage("switchDelay") var switchDelay: Double = 2.0
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

        switch newState {
        case .working:
            appSwitcher.switchToBreakApp(bundleID: breakAppBundleID, delay: switchDelay)
        case .waitingForUser:
            appSwitcher.switchToSourceApp(bundleID: sourceAppBundleID)
        case .idle:
            if oldState == .working || oldState == .waitingForUser {
                appSwitcher.switchToSourceApp(bundleID: sourceAppBundleID)
            }
        }
    }

    func checkHookInstalled() {
        isHookInstalled = HookInstaller.isInstalled()
    }
}
