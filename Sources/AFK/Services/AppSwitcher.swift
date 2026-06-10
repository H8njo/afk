import AppKit

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
        pendingSwitch?.cancel()
        pendingSwitch = nil
        activateApp(bundleID: bundleID)
    }

    private func activateApp(bundleID: String) {
        if let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .first {
            app.activate(options: .activateIgnoringOtherApps)
        } else {
            // App not running — launch it
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            if let url = url {
                NSWorkspace.shared.openApplication(
                    at: url,
                    configuration: NSWorkspace.OpenConfiguration()
                )
            }
        }
    }
}
