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
    @State private var accessibilityGranted = false

    private let systemSounds = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass",
        "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi",
        "Submarine", "Tink"
    ]

    var body: some View {
        Form {
            Section("App Switching") {
                Toggle("Switch to break app while working", isOn: $appState.switchToBreakApp)

                if appState.switchToBreakApp {
                    Picker("Break App", selection: $appState.breakAppBundleID) {
                        Text("Previous App (Cmd+Tab)").tag(AppSwitcher.previousAppID)
                        Divider()
                        ForEach(installedApps) { app in
                            Text(app.name).tag(app.id)
                        }
                    }
                }

                Picker("On Completion", selection: $appState.completionMode) {
                    ForEach(AppState.CompletionMode.allCases, id: \.rawValue) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }

                if appState.completionMode == AppState.CompletionMode.autoSwitch.rawValue {
                    Picker("Source App (AI tool)", selection: $appState.sourceAppBundleID) {
                        Text("Session App (Auto)").tag(AppSwitcher.autoSourceID)
                        Divider()
                        ForEach(installedApps) { app in
                            Text(app.name).tag(app.id)
                        }
                    }
                }

                HStack {
                    Text("Switch delay: \(String(format: "%.1f", appState.switchDelay))s")
                    Slider(value: $appState.switchDelay, in: 0...10, step: 0.5)
                }
            }

            if appState.completionMode == AppState.CompletionMode.notify.rawValue {
                Section("Notification") {
                    HStack {
                        Picker("Sound", selection: $appState.notificationSound) {
                            Text("None").tag("")
                            Divider()
                            ForEach(systemSounds, id: \.self) { sound in
                                Text(sound).tag(sound)
                            }
                        }
                        Button("▶") {
                            if !appState.notificationSound.isEmpty {
                                NSSound(named: NSSound.Name(appState.notificationSound))?.play()
                            }
                        }
                    }

                    HStack {
                        Text("Duration: \(Int(appState.notificationDuration))s")
                        Slider(value: $appState.notificationDuration, in: 3...30, step: 1)
                    }
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
                HStack {
                    if accessibilityGranted {
                        Label("Accessibility Granted", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Label("Accessibility Not Granted", systemImage: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                    }
                    Spacer()
                    if !accessibilityGranted {
                        Button("Grant") {
                            let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
                            AXIsProcessTrustedWithOptions(opts)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                accessibilityGranted = AXIsProcessTrusted()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Open Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
                if !accessibilityGranted {
                    Text("Required for app switching. After rebuild, toggle OFF → ON to re-trust.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 400)
        .onAppear {
            loadInstalledApps()
            accessibilityGranted = AXIsProcessTrusted()
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
