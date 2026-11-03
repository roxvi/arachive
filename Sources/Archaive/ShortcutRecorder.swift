import AppKit
import SwiftUI

/// The same click-to-record control works in the status menu and welcome tour.
struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: Shortcut
    let keySize: CGFloat
    let save: (Shortcut) -> String?
    let recordingChanged: (Bool) -> Void

    func makeNSView(context: Context) -> ShortcutRecordButton {
        let button = ShortcutRecordButton()
        button.keySize = keySize
        button.shortcut = shortcut
        button.save = save
        button.recordingChanged = recordingChanged
        return button
    }

    func updateNSView(_ button: ShortcutRecordButton, context: Context) {
        button.shortcut = shortcut
        button.save = save
        button.recordingChanged = recordingChanged
        button.needsDisplay = true
    }

    static func dismantleNSView(_ button: ShortcutRecordButton, coordinator: ()) {
        button.stopRecording()
    }
}

final class ShortcutRecordButton: NSButton {
    var shortcut = Shortcut.standard
    var keySize: CGFloat = 50
    var save: ((Shortcut) -> String?)?
    var recordingChanged: ((Bool) -> Void)?
    private var monitor: Any?
    private var message: String?
    private var liveSymbols = ["…"]
    private var resignObserver: NSObjectProtocol?
    private var recording: Bool { monitor != nil }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        title = ""
        target = self
        action = #selector(startRecording)
        setAccessibilityLabel("Keep awake keyboard shortcut")
        toolTip = "Click, then press a letter or number with Command, Option, or Control. Escape cancels."
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: keySize * 5 + (keySize > 24 ? 32 : 16), height: keySize)
    }

    override func accessibilityValue() -> Any? { recording ? (message ?? "Press a shortcut. Escape cancels.") : shortcut.label }

    @objc private func startRecording() {
        guard !recording else { stopRecording(); return }
        message = nil
        liveSymbols = ["…"]
        window?.makeFirstResponder(self)
        recordingChanged?(true)
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.stopRecording()
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .flagsChanged {
                self.liveSymbols = self.modifierSymbols(event.modifierFlags) + ["…"]
                self.needsDisplay = true
                return event
            }
            if event.type != .keyDown {
                self.stopRecording()
                return event
            }
            if event.keyCode == 53 { self.stopRecording(); return nil }
            guard !event.isARepeat else { return nil }
            guard let candidate = Shortcut.captured(keyCode: event.keyCode, flags: event.modifierFlags) else {
                self.liveSymbols = self.modifierSymbols(event.modifierFlags) + [Shortcut.keys.first { $0.1 == UInt32(event.keyCode) }?.0 ?? "?"]
                self.message = "Include Command, Option, or Control with a letter or number."
                self.toolTip = self.message
                self.needsDisplay = true
                return nil
            }
            self.liveSymbols = candidate.symbols
            if let error = self.save?(candidate) {
                self.message = "In use. Try another."
                self.toolTip = error
                self.needsDisplay = true
                NSAccessibility.post(element: self, notification: .valueChanged)
                return nil
            }
            self.shortcut = candidate
            self.stopRecording()
            return nil
        }
        needsDisplay = true
        NSAccessibility.post(element: self, notification: .valueChanged)
    }

    func stopRecording() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        message = nil
        recordingChanged?(false)
        needsDisplay = true
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { stopRecording() }
        super.viewWillMove(toWindow: newWindow)
    }

    override func draw(_ dirtyRect: NSRect) {
        let gap: CGFloat = keySize > 24 ? 8 : 4
        let symbols = recording ? liveSymbols : shortcut.symbols
        let width = CGFloat(symbols.count) * keySize + CGFloat(symbols.count - 1) * gap
        for (index, symbol) in symbols.enumerated() {
            let rect = NSRect(x: (bounds.width - width) / 2 + CGFloat(index) * (keySize + gap), y: (bounds.height - keySize) / 2, width: keySize, height: keySize)
            NSColor.labelColor.withAlphaComponent(0.09).setFill()
            NSBezierPath(roundedRect: rect, xRadius: keySize > 24 ? 10 : 5, yRadius: keySize > 24 ? 10 : 5).fill()
            if recording {
                (message == nil ? NSColor.controlAccentColor : NSColor.systemRed).setStroke()
                let border = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: keySize > 24 ? 10 : 5, yRadius: keySize > 24 ? 10 : 5)
                border.lineWidth = 2
                border.stroke()
            }
            drawText(symbol, in: rect, size: keySize > 24 ? 27 : 14)
        }
    }

    private func modifierSymbols(_ flags: NSEvent.ModifierFlags) -> [String] {
        let pairs: [(NSEvent.ModifierFlags, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return pairs.filter { flags.contains($0.0) }.map { $0.1 }
    }

    private func drawText(_ text: String, in rect: NSRect, size: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: NSColor.labelColor]
        let textSize = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2), withAttributes: attributes)
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }
}
