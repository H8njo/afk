import AppKit
import SwiftUI

struct MenuBarIconView: View {
    @ObservedObject var appState: AppState
    @State private var rotationDeg: Double = 0
    @State private var timer: Timer?

    var body: some View {
        Group {
            if appState.isPaused {
                Image(systemName: "pause.circle")
            } else {
                Image(nsImage: MenuBarIcon.create(rotation: rotationDeg))
            }
        }
        .onChange(of: appState.currentState) { newState in
            if newState == .working {
                startSpinning()
            } else {
                stopSpinning()
            }
        }
        .onAppear {
            if appState.currentState == .working {
                startSpinning()
            }
        }
    }

    private func startSpinning() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            Task { @MainActor in
                rotationDeg += 4
                if rotationDeg >= 360 { rotationDeg -= 360 }
            }
        }
    }

    private func stopSpinning() {
        timer?.invalidate()
        timer = nil
        rotationDeg = 0
    }
}

struct MenuBarIcon {
    static func create(size: CGFloat = 18, rotation: Double = 0) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let ctx = NSGraphicsContext.current!.cgContext
            let f = size / 36.0

            let cx = 18 * f
            let cy = 18 * f

            // Apply rotation around center
            ctx.translateBy(x: cx, y: cy)
            ctx.rotate(by: rotation * .pi / 180)
            ctx.translateBy(x: -cx, y: -cy)

            ctx.setFillColor(NSColor.black.cgColor)
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineWidth(max(1.5, 2 * f))
            ctx.setLineCap(.round)

            let rx = 15 * f
            let ry = 6 * f

            for idx in 0..<3 {
                let angleDeg = Double(idx) * 60.0
                let rot = angleDeg * .pi / 180

                let path = CGMutablePath()
                var first = true

                for t in stride(from: 0.0, through: 360.0, by: 2.0) {
                    if idx == 2 && t > 35 && t < 75 {
                        first = true
                        continue
                    }

                    let rad = t * .pi / 180
                    let x = rx * cos(rad)
                    let y = ry * sin(rad)
                    let px = cx + x * cos(rot) - y * sin(rot)
                    let py = cy + x * sin(rot) + y * cos(rot)

                    if first {
                        path.move(to: CGPoint(x: px, y: py))
                        first = false
                    } else {
                        path.addLine(to: CGPoint(x: px, y: py))
                    }
                }

                ctx.addPath(path)
                ctx.strokePath()
            }

            let gapT = 35.0 * .pi / 180
            let rot120 = 120.0 * .pi / 180
            let ex = rx * cos(gapT)
            let ey = ry * sin(gapT)
            let dotX = cx + ex * cos(rot120) - ey * sin(rot120)
            let dotY = cy + ex * sin(rot120) + ey * cos(rot120)
            let dotR = 2.2 * f
            ctx.fillEllipse(in: CGRect(x: dotX - dotR, y: dotY - dotR, width: dotR * 2, height: dotR * 2))

            let sr = 3.5 * f
            let ir = 1.2 * f
            let corePath = CGMutablePath()
            corePath.move(to: CGPoint(x: cx, y: cy - sr))
            corePath.addLine(to: CGPoint(x: cx + ir, y: cy - ir))
            corePath.addLine(to: CGPoint(x: cx + sr, y: cy))
            corePath.addLine(to: CGPoint(x: cx + ir, y: cy + ir))
            corePath.addLine(to: CGPoint(x: cx, y: cy + sr))
            corePath.addLine(to: CGPoint(x: cx - ir, y: cy + ir))
            corePath.addLine(to: CGPoint(x: cx - sr, y: cy))
            corePath.addLine(to: CGPoint(x: cx - ir, y: cy - ir))
            corePath.closeSubpath()
            ctx.addPath(corePath)
            ctx.fillPath()

            return true
        }

        image.isTemplate = true
        return image
    }
}
