import AppKit
import QuartzCore

/// Draws both states from the same geometry so the crescent fills into a sun.
final class StatusIconAnimator {
    private var timer: Timer?
    private var target: Bool?
    private var progress: CGFloat = 0

    deinit { timer?.invalidate() }

    func update(button: NSStatusBarButton, awake: Bool) {
        guard target != awake else { return }
        let initial = target == nil
        target = awake
        timer?.invalidate()
        let end: CGFloat = awake ? 1 : 0
        let description = awake ? "Archaive: keeping awake" : "Archaive: normal sleep"
        button.setAccessibilityLabel(description)
        guard !initial, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            progress = end
            button.image = Self.image(progress: end, description: description)
            return
        }

        let start = progress
        let began = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self, weak button] timer in
            guard let self, let button else { timer.invalidate(); return }
            let elapsed = min((CACurrentMediaTime() - began) / 0.45, 1)
            let eased = CGFloat(elapsed * elapsed * (3 - 2 * elapsed))
            self.progress = start + (end - start) * eased
            button.image = Self.image(progress: self.progress, description: description)
            if elapsed >= 1 { timer.invalidate(); self.timer = nil }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private static func image(progress: CGFloat, description: String) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            let radius: CGFloat = 6 - progress * 1.5
            NSBezierPath(ovalIn: NSRect(x: 9 - radius, y: 9 - radius,
                                      width: radius * 2, height: radius * 2)).fill()

            // Slide the crescent's cutout out of the disc as its rays emerge.
            let offset = 3 + progress * 10
            let cutout = NSBezierPath(ovalIn: NSRect(x: 9 + offset - 5.7, y: 11 - 5.7,
                                                   width: 11.4, height: 11.4))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            cutout.fill()
            NSGraphicsContext.restoreGraphicsState()

            let rays = max(0, (progress - 0.3) / 0.7)
            if rays > 0 {
                NSColor.black.setStroke()
                let path = NSBezierPath()
                path.lineWidth = 1.4 * rays
                path.lineCapStyle = .round
                for index in 0..<8 {
                    let angle = CGFloat(index) * .pi / 4 + (1 - progress) * .pi / 8
                    let inner: CGFloat = 6.2
                    let outer = inner + 1.5 * rays
                    path.move(to: NSPoint(x: 9 + cos(angle) * inner, y: 9 + sin(angle) * inner))
                    path.line(to: NSPoint(x: 9 + cos(angle) * outer, y: 9 + sin(angle) * outer))
                }
                path.stroke()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = description
        return image
    }
}
