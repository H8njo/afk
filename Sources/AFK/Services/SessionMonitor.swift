import Foundation
import AppKit

class SessionMonitor {
    private var source: DispatchSourceFileSystemObject?
    private var pollTimer: DispatchSourceTimer?
    private var dirFD: Int32 = -1
    private let sessionsPath: String
    private let onChange: (AppState.AIState, [SessionInfo]) -> Void
    private var lastStates: [String: AppState.AIState] = [:]

    static let sessionsDirectory: String = {
        let path = NSHomeDirectory() + "/.afk/sessions"
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }()

    init(onChange: @escaping (AppState.AIState, [SessionInfo]) -> Void) {
        self.sessionsPath = Self.sessionsDirectory
        self.onChange = onChange
    }

    func start() {
        dirFD = open(sessionsPath, O_EVTONLY)
        guard dirFD >= 0 else {
            print("AFK: Failed to open sessions directory for monitoring")
            return
        }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: dirFD,
            eventMask: .write,
            queue: DispatchQueue.global(qos: .userInitiated)
        )

        source?.setEventHandler { [weak self] in
            self?.readAndAggregate()
        }

        source?.setCancelHandler { [weak self] in
            if let fd = self?.dirFD, fd >= 0 {
                close(fd)
            }
        }

        source?.resume()

        // Poll every 5s to catch killed apps
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in
            self?.readAndAggregate()
        }
        timer.resume()
        pollTimer = timer

        // Initial read
        readAndAggregate()
    }

    func stop() {
        source?.cancel()
        source = nil
        pollTimer?.cancel()
        pollTimer = nil
    }

    func refresh() {
        readAndAggregate()
    }

    private func readAndAggregate() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: sessionsPath) else { return }

        let runningBundleIDs = Set(
            NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier }
        )

        var states: [String: AppState.AIState] = [:]
        var sessions: [SessionInfo] = []

        for file in files where file.hasSuffix(".json") {
            let path = (sessionsPath as NSString).appendingPathComponent(file)
            guard let data = fm.contents(atPath: path),
                  let json = try? JSONDecoder().decode(SessionState.self, from: data) else {
                continue
            }

            let ts = Self.parseISO8601(json.ts)

            // Remove stale sessions (older than 5 minutes)
            if let ts = ts, Date().timeIntervalSince(ts) > 300 {
                try? fm.removeItem(atPath: path)
                continue
            }

            // Remove sessions whose app is no longer running
            if let bundleID = json.appBundle, !bundleID.isEmpty,
               !runningBundleIDs.contains(bundleID) {
                try? fm.removeItem(atPath: path)
                continue
            }

            states[json.sessionId] = json.state
            sessions.append(SessionInfo(
                id: json.sessionId,
                state: json.state,
                prompt: json.prompt,
                app: json.app,
                appBundle: json.appBundle,
                updatedAt: ts
            ))
        }

        sessions.sort { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }

        let aggregated = Self.aggregate(states)
        lastStates = states
        onChange(aggregated, sessions)
    }

    static func aggregate(_ states: [String: AppState.AIState]) -> AppState.AIState {
        let values = Array(states.values)
        if values.isEmpty { return .idle }

        // Any session waiting → user needs to return
        if values.contains(.waitingForUser) { return .waitingForUser }

        // All working → break time
        if values.allSatisfy({ $0 == .working }) { return .working }

        // Mix of idle and working → still working
        if values.contains(.working) { return .working }

        return .idle
    }

    private static func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    deinit {
        stop()
    }
}

struct SessionInfo: Identifiable {
    let id: String
    let state: AppState.AIState
    let prompt: String?
    let app: String?
    let appBundle: String?
    let updatedAt: Date?

    var displayTitle: String {
        if let prompt = prompt, !prompt.isEmpty {
            let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count > 40 {
                return String(trimmed.prefix(40)) + "..."
            }
            return trimmed
        }
        return String(id.prefix(8))
    }

    var displayApp: String? {
        guard let app = app, !app.isEmpty else { return nil }
        return app
    }

    func resolveBundleID() -> String? {
        if let bundle = appBundle, !bundle.isEmpty { return bundle }
        guard let app = app, !app.isEmpty else { return nil }
        return AppSwitcher.bundleID(forAppName: app)
    }

    var menuLabel: String {
        var parts = [displayTitle, stateLabel]
        if let app = displayApp {
            parts.insert(app, at: 0)
        }
        return parts.joined(separator: " — ")
    }

    var stateLabel: String {
        switch state {
        case .working: return "Working"
        case .waitingForUser: return "Done"
        case .idle: return "Idle"
        }
    }
}

struct SessionState: Codable {
    let state: AppState.AIState
    let sessionId: String
    let prompt: String?
    let app: String?
    let appBundle: String?
    let ts: String

    enum CodingKeys: String, CodingKey {
        case state
        case sessionId = "session_id"
        case prompt
        case app
        case appBundle = "app_bundle"
        case ts
    }
}
