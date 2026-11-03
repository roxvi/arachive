import AppKit
import Carbon

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let keys: [(String, UInt32)] = [
        ("A", 0), ("B", 11), ("C", 8), ("D", 2), ("E", 14), ("F", 3),
        ("G", 5), ("H", 4), ("I", 34), ("J", 38), ("K", 40), ("L", 37),
        ("M", 46), ("N", 45), ("O", 31), ("P", 35), ("Q", 12), ("R", 15),
        ("S", 1), ("T", 17), ("U", 32), ("V", 9), ("W", 13), ("X", 7),
        ("Y", 16), ("Z", 6), ("0", 29), ("1", 18), ("2", 19), ("3", 20),
        ("4", 21), ("5", 23), ("6", 22), ("7", 26), ("8", 28), ("9", 25)
    ]
    static let modifierKeys: [(String, String, UInt32)] = [
        ("Control", "⌃", UInt32(controlKey)), ("Option", "⌥", UInt32(optionKey)),
        ("Shift", "⇧", UInt32(shiftKey)), ("Command", "⌘", UInt32(cmdKey))
    ]
    static let standard = Shortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey | optionKey | controlKey))
    var isValid: Bool {
        Self.keys.contains { $0.1 == keyCode } &&
        modifiers & UInt32(cmdKey | optionKey | controlKey) != 0 &&
        modifiers & ~UInt32(cmdKey | optionKey | controlKey | shiftKey) == 0
    }
    static func captured(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Shortcut? {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        guard !flags.contains(.function) else { return nil }
        let mapping: [(NSEvent.ModifierFlags, UInt32)] = [
            (.command, UInt32(cmdKey)), (.option, UInt32(optionKey)),
            (.control, UInt32(controlKey)), (.shift, UInt32(shiftKey))
        ]
        let shortcut = Shortcut(keyCode: UInt32(keyCode), modifiers: mapping.reduce(0) { $0 | (flags.contains($1.0) ? $1.1 : 0) })
        return shortcut.isValid ? shortcut : nil
    }
    var symbols: [String] {
        Self.modifierKeys.filter { modifiers & $0.2 != 0 }.map { $0.1 } + [Self.keys.first { $0.1 == keyCode }?.0 ?? "?"]
    }
    var label: String { symbols.joined() }
    static func load(from defaults: UserDefaults = .standard) -> Shortcut {
        guard let data = defaults.data(forKey: "keepAwakeShortcut"),
              let value = try? JSONDecoder().decode(Self.self, from: data), value.isValid else { return .standard }
        return value
    }
    func save(to defaults: UserDefaults = .standard) {
        guard isValid, let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: "keepAwakeShortcut")
    }
}

final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private(set) var shortcut = Shortcut.load()
    var action: (() -> Void)?

    func register(_ candidate: Shortcut? = nil) -> Bool {
        let value = candidate ?? shortcut
        guard value.isValid else { return false }
        if ref != nil && value == shortcut { return true }
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
                guard let context else { return OSStatus(eventNotHandledErr) }
                Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue().action?()
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard installed == noErr else { return false }
        }
        // Keep the previous shortcut working if the new combination is unavailable.
        var replacement: EventHotKeyRef?
        guard RegisterEventHotKey(value.keyCode, value.modifiers, EventHotKeyID(signature: 0x53554D52, id: 1), GetApplicationEventTarget(), 0, &replacement) == noErr else { return false }
        if let ref { UnregisterEventHotKey(ref) }
        ref = replacement
        shortcut = value
        return true
    }

    func suspend() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}
