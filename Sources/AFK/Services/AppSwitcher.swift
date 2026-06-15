import AppKit

class AppSwitcher {
    static let previousAppID = "__previous__"
    static let autoSourceID = "__auto__"

    static func bundleID(forAppName name: String) -> String? {
        let known: [String: String] = [
            "Terminal": "com.apple.Terminal",
            "iTerm": "com.googlecode.iterm2",
            "VS Code": "com.microsoft.VSCode",
            "Cursor": "com.todesktop.230313mzl4w4u92",
            "Warp": "dev.warp.Warp-Stable",
        ]
        if let id = known[name] { return id }
        let nameLower = name.lowercased()
        for app in NSWorkspace.shared.runningApplications {
            guard let localName = app.localizedName,
                  let bundleID = app.bundleIdentifier else { continue }
            if localName == name || localName.lowercased().contains(nameLower) {
                return bundleID
            }
        }
        return nil
    }

    private var pendingSwitch: DispatchWorkItem?
    private var previousAppBundleID: String?
    private var currentAppBundleID: String?

    init() {
        currentAppBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func appDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier else { return }
        // Don't track AFK itself
        guard bundleID != Bundle.main.bundleIdentifier else { return }
        previousAppBundleID = currentAppBundleID
        currentAppBundleID = bundleID
    }

    func switchToBreakApp(bundleID: String, delay: TimeInterval) {
        pendingSwitch?.cancel()
        // Capture previous app now, before the delay
        let targetID = resolveBreakApp(bundleID)
        guard let targetID = targetID else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.activateApp(bundleID: targetID)
        }
        pendingSwitch = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func switchToSourceApp(bundleID: String) {
        pendingSwitch?.cancel()
        pendingSwitch = nil
        activateApp(bundleID: bundleID)
    }

    private func resolveBreakApp(_ bundleID: String) -> String? {
        if bundleID == Self.previousAppID {
            return previousAppBundleID
        }
        return bundleID
    }

    private func activateApp(bundleID: String) {
        if let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .first {
            app.activate(options: .activateIgnoringOtherApps)
        } else {
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            if let url = url {
                NSWorkspace.shared.openApplication(
                    at: url,
                    configuration: NSWorkspace.OpenConfiguration()
                )
            }
        }
    }

    static func focusSourceApp(bundleID: String) {
        if let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .first {
            app.activate(options: .activateIgnoringOtherApps)
        }
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
