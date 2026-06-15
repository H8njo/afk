import AppKit
import SwiftUI

@MainActor
class NotificationManager {
    static let shared = NotificationManager()

    private struct NotificationEntry {
        let window: NSWindow
        let timer: DispatchWorkItem
        let id: String
    }

    private var entries: [NotificationEntry] = []
    private let bannerWidth: CGFloat = 340
    private let bannerHeight: CGFloat = 160
    private let spacing: CGFloat = 10

    func notify(session: SessionInfo) {
        let soundName = UserDefaults.standard.string(forKey: "notificationSound") ?? "Ping"
        if !soundName.isEmpty {
            NSSound(named: NSSound.Name(soundName))?.play()
        }

        let appName = session.displayApp ?? "AI"
        let prompt = session.displayTitle
        let bundleID = session.resolveBundleID()
        let entryID = "\(session.id)-\(entries.count)-\(CACurrentMediaTime())"

        let banner = NotificationBanner(
            appName: appName,
            prompt: prompt,
            onOpen: { [weak self] in
                if let id = bundleID {
                    AppSwitcher.focusSourceApp(bundleID: id)
                }
                self?.dismissByID(entryID)
            },
            onDismiss: { [weak self] in
                self?.dismissByID(entryID)
            }
        )

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: bannerWidth, height: bannerHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        w.level = .screenSaver
        w.backgroundColor = .clear
        w.isOpaque = false
        w.hasShadow = true
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.canJoinAllSpaces, .stationary]
        w.contentView = NSHostingView(rootView: banner)

        let timer = DispatchWorkItem { [weak self] in
            self?.dismissByID(entryID)
        }
        let duration = UserDefaults.standard.double(forKey: "notificationDuration")
        DispatchQueue.main.asyncAfter(deadline: .now() + (duration > 0 ? duration : 8), execute: timer)

        entries.append(NotificationEntry(window: w, timer: timer, id: entryID))
        repositionAll()
        w.orderFrontRegardless()
        AppState.log("notify: entries=\(entries.count), positions=\(entries.map { "\($0.window.frame.origin.y)" }.joined(separator: ","))")
    }

    private func dismissByID(_ id: String) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = entries.remove(at: idx)
        entry.timer.cancel()
        entry.window.close()
        repositionAll()
    }

    private func repositionAll() {
        guard let screen = NSScreen.main else { return }
        let sf = screen.visibleFrame

        for (i, entry) in entries.enumerated() {
            let x = sf.maxX - bannerWidth - 16
            let y = sf.maxY - CGFloat(i + 1) * (bannerHeight + spacing)
            entry.window.setFrame(
                NSRect(x: x, y: y, width: bannerWidth, height: bannerHeight),
                display: true
            )
        }
    }

    func dismiss() {
        for entry in entries {
            entry.timer.cancel()
            entry.window.close()
        }
        entries.removeAll()
    }
}

struct NotificationBanner: View {
    let appName: String
    let prompt: String
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "atom")
                    .font(.title3)
                Text("AFK")
                    .font(.subheadline.bold())
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text("\(appName) — Done")
                .font(.headline)

            Text(prompt)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)

            Button(action: onOpen) {
                Text("Open \(appName)")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .frame(width: 340, height: 160)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
