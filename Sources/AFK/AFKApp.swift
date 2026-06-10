import SwiftUI

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
