import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(appState.statusText)
            .font(.headline)

        Divider()

        if !appState.sessions.isEmpty {
            ForEach(appState.sessions) { session in
                Button(session.menuLabel) {
                    let bundleID = session.resolveBundleID() ?? appState.sourceAppBundleID
                    AppSwitcher.focusSourceApp(bundleID: bundleID)
                }
            }

            Divider()
        }

        Toggle("Pause", isOn: $appState.isPaused)
            .keyboardShortcut("p")

        Divider()

        Button("Settings...") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",")

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
