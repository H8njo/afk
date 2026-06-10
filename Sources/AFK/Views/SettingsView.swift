import SwiftUI

struct InstalledApp: Identifiable, Hashable {
    let id: String  // bundleIdentifier
    let name: String
}

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var installedApps: [InstalledApp] = []
    @State private var hookError: String?
    @State private var showHookError = false

    var body: some View {
        Form {
            Section("App Switching") {
                Picker("Break App", selection: $appState.breakAppBundleID) {
                    Text("Previous App (Cmd+Tab)").tag(AppSwitcher.previousAppID)
                    Divider()
                    ForEach(installedApps) { app in
                        Text(app.name).tag(app.id)
                    }
                }

                Picker("Source App (AI tool)", selection: $appState.sourceAppBundleID) {
                    ForEach(installedApps) { app in
                        Text(app.name).tag(app.id)
                    }
                }

                HStack {
                    Text("Switch delay: \(String(format: "%.1f", appState.switchDelay))s")
                    Slider(value: $appState.switchDelay, in: 0...10, step: 0.5)
                }
            }

            Section("Claude Code Hook") {
                if appState.isHookInstalled {
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)

                    Button("Uninstall Hook") {
                        do {
                            try HookInstaller.uninstall()
                            appState.checkHookInstalled()
                        } catch {
                            hookError = error.localizedDescription
                            showHookError = true
                        }
                    }
                } else {
                    Label("Not Installed", systemImage: "xmark.circle")
                        .foregroundColor(.secondary)

                    Button("Install Hook") {
                        do {
                            try HookInstaller.install()
                            appState.checkHookInstalled()
                        } catch {
                            hookError = error.localizedDescription
                            showHookError = true
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Section("Permissions") {
                if AXIsProcessTrusted() {
                    Label("Accessibility Granted", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Label("Accessibility Not Granted", systemImage: "exclamationmark.triangle")
                        .foregroundColor(.orange)

                    Button("Grant Accessibility") {
                        let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
                        AXIsProcessTrustedWithOptions(opts)
                    }
                    .buttonStyle(.borderedProminent)

                    Text("Required for automatic app switching.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 400)
        .onAppear {
            loadInstalledApps()
        }
        .alert("Hook Installation Error", isPresented: $showHookError) {
            Button("OK") {}
        } message: {
            Text(hookError ?? "Unknown error")
        }
    }

    private func loadInstalledApps() {
        let workspace = NSWorkspace.shared
        let apps = workspace.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> InstalledApp? in
                guard let bundleID = app.bundleIdentifier,
                      let name = app.localizedName else { return nil }
                return InstalledApp(id: bundleID, name: name)
            }
            .sorted { $0.name < $1.name }

        // Deduplicate
        var seen = Set<String>()
        installedApps = apps.filter { seen.insert($0.id).inserted }

        // Ensure current selections are in the list
        let knownApps: [(String, String)] = [
            ("com.apple.Safari", "Safari"),
            ("com.apple.Terminal", "Terminal"),
            ("com.googlecode.iterm2", "iTerm2"),
            ("com.google.Chrome", "Google Chrome"),
        ]
        for (id, name) in knownApps {
            if !seen.contains(id) {
                installedApps.append(InstalledApp(id: id, name: name))
                seen.insert(id)
            }
        }

        installedApps.sort { $0.name < $1.name }
    }
}
