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
    private let bannerWidth: CGFloat = 320
    private let bannerHeight: CGFloat = 150
    private let spacing: CGFloat = 4

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
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(.green.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.green)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Task Complete")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(appName)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 22, height: 22)
                        .background(.quaternary.opacity(0.5), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()
                .padding(.horizontal, 12)

            Text(prompt)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            Button(action: onOpen) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 11, weight: .medium))
                    Text("Back to \(appName)")
                        .font(.system(size: 12, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(width: 320)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.primary.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
    }
}
