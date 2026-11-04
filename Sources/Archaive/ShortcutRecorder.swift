import AppKit
import SwiftUI

/// A focused recorder shared by onboarding and the menu-bar shortcut popover.
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
    private(set) var liveSymbols = ["…"]
    private var resignObserver: NSObjectProtocol?
    private(set) var recording = false

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

    override func mouseDown(with event: NSEvent) { startRecording() }

    @objc func startRecording() {
        guard !recording else { stopRecording(); return }
        recording = true
        message = nil
        liveSymbols = ["…"]
        recordingChanged?(true)
        NSApp?.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(self)
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            self?.stopRecording()
        }
        // Mouse events cancel capture; keyboard input goes through the key window's
        // first responder, including Command combinations via performKeyEquivalent.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.stopRecording()
            return event
        }
        needsDisplay = true
        NSAccessibility.post(element: self, notification: .valueChanged)
    }

    override func keyDown(with event: NSEvent) {
        if !capture(keyCode: event.keyCode, flags: event.modifierFlags, repeating: event.isARepeat) { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if recording && window?.firstResponder === self {
            return capture(keyCode: event.keyCode, flags: event.modifierFlags, repeating: event.isARepeat)
        }
        return super.performKeyEquivalent(with: event)
    }

    override func flagsChanged(with event: NSEvent) {
        guard recording else { super.flagsChanged(with: event); return }
        updateModifiers(event.modifierFlags)
    }

    func updateModifiers(_ flags: NSEvent.ModifierFlags) {
        guard recording else { return }
        liveSymbols = modifierSymbols(flags) + ["…"]
        needsDisplay = true
    }

    @discardableResult
    func capture(keyCode: UInt16, flags: NSEvent.ModifierFlags, repeating: Bool = false) -> Bool {
        guard recording else { return false }
        if keyCode == 53 { stopRecording(); return true }
        guard !repeating else { return true }
        guard let candidate = Shortcut.captured(keyCode: keyCode, flags: flags) else {
            liveSymbols = modifierSymbols(flags) + [Shortcut.keys.first { $0.1 == UInt32(keyCode) }?.0 ?? "?"]
            message = "Include Command, Option, or Control with a letter or number."
            toolTip = message
            needsDisplay = true
            return true
        }
        liveSymbols = candidate.symbols
        if let error = save?(candidate) {
            message = error
            toolTip = error
            needsDisplay = true
            NSAccessibility.post(element: self, notification: .valueChanged)
            return true
        }
        shortcut = candidate
        stopRecording()
        return true
    }

    func stopRecording() {
        guard recording else { return }
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        message = nil
        toolTip = "Click to record a shortcut. Escape cancels."
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
                (message == nil ? NSColor(srgbRed: 1, green: 0.66, blue: 0.43, alpha: 1) : NSColor.systemRed).setStroke()
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

private final class ShortcutActionButton: NSButton {
    var invoke: (() -> Void)?
    init(title: String, action: @escaping () -> Void) {
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        font = .menuFont(ofSize: 13)
        target = self
        self.action = #selector(clicked)
        invoke = action
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func clicked() { invoke?() }
}

/// A regular-height menu row. Only the shortcut badge opens the editor.
final class ShortcutMenuRow: NSView {
    init(shortcut: Shortcut, awake: Bool, enabled: Bool, toggle: @escaping () -> Void, edit: @escaping () -> Void) {
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        let toggleButton = ShortcutActionButton(title: awake ? "✓  Toggle Keep Awake" : "    Toggle Keep Awake", action: toggle)
        toggleButton.alignment = .left
        toggleButton.frame = NSRect(x: 8, y: 1, width: 174, height: 22)
        toggleButton.isEnabled = enabled
        toggleButton.setAccessibilityLabel("Toggle Keep Awake")
        addSubview(toggleButton)
        let editButton = ShortcutActionButton(title: shortcut.label, action: edit)
        editButton.frame = NSRect(x: 186, y: 1, width: 80, height: 22)
        editButton.toolTip = "Edit keyboard shortcut"
        editButton.setAccessibilityLabel("Edit keyboard shortcut, \(shortcut.label)")
        addSubview(editButton)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Recording needs a key window, which a tracking NSMenu does not provide.
final class ShortcutPopover: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private var recorder: ShortcutRecordButton?

    func show(from button: NSStatusBarButton, shortcut: Shortcut,
              save: @escaping (Shortcut) -> String?, recordingChanged: @escaping (Bool) -> Void) {
        popover.performClose(nil)
        let controller = NSViewController()
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 282, height: 132))
        let title = NSTextField(labelWithString: "Keyboard shortcut")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.frame = NSRect(x: 16, y: 103, width: 200, height: 18)
        content.addSubview(title)
        let keys = ShortcutRecordButton(frame: NSRect(x: 16, y: 48, width: 250, height: 40))
        keys.keySize = 32
        keys.shortcut = shortcut
        keys.save = save
        keys.recordingChanged = { [weak self] recording in
            recordingChanged(recording)
            if !recording {
                DispatchQueue.main.async { self?.popover.performClose(nil) }
            }
        }
        content.addSubview(keys)
        let hint = NSTextField(wrappingLabelWithString: "Press your new shortcut. Esc cancels.\nUse ⌘, ⌥ or ⌃ with a letter or number.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.alignment = .center
        hint.frame = NSRect(x: 16, y: 10, width: 250, height: 30)
        content.addSubview(hint)
        controller.view = content
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        recorder = keys
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        keys.startRecording()
    }

    func popoverDidClose(_ notification: Notification) {
        recorder?.stopRecording()
        recorder = nil
    }
}
