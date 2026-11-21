import Carbon.HIToolbox
import CoreGraphics
import Foundation

// Lives on the sharing queue. The timer releases a drag if the phone disappears.
final class PhoneInput {
    private let display: CGDirectDisplayID
    private let dragTimer: DispatchSourceTimer
    private var lastDrag: CGPoint?
    private let source = CGEventSource(stateID: .privateState)

    init(display: CGDirectDisplayID, queue: DispatchQueue) {
        self.display = display
        dragTimer = DispatchSource.makeTimerSource(queue: queue)
        dragTimer.schedule(deadline: .distantFuture)
        dragTimer.setEventHandler { [weak self] in self?.releaseDrag() }
        dragTimer.activate()
    }

    func perform(_ command: PhoneControl.Command) -> Bool {
        guard CGDisplayIsActive(display) != 0, CGPreflightPostEventAccess() else { return false }
        let bounds = CGDisplayBounds(display)
        guard !bounds.isEmpty else { return false }

        func location(_ point: PhoneControl.Point) -> CGPoint {
            CGPoint(x: bounds.minX + point.x * (bounds.width - 1),
                    y: bounds.minY + point.y * (bounds.height - 1))
        }

        switch command {
        case .click(let point), .doubleClick(let point), .rightClick(let point):
            releaseDrag()
            let position = location(point)
            mouse(.mouseMoved, at: position)
            if case .rightClick = command {
                mouse(.rightMouseDown, at: position, button: .right, clicks: 1)
                mouse(.rightMouseUp, at: position, button: .right, clicks: 1)
            } else {
                mouse(.leftMouseDown, at: position, clicks: 1)
                mouse(.leftMouseUp, at: position, clicks: 1)
                if case .doubleClick = command {
                    mouse(.leftMouseDown, at: position, clicks: 2)
                    mouse(.leftMouseUp, at: position, clicks: 2)
                }
            }
        case .dragStart(let point):
            releaseDrag()
            let position = location(point)
            mouse(.mouseMoved, at: position)
            mouse(.leftMouseDown, at: position, clicks: 1)
            updateDrag(position)
        case .dragMove(let point):
            guard lastDrag != nil else { return false }
            let position = location(point)
            mouse(.leftMouseDragged, at: position, clicks: 1)
            updateDrag(position)
        case .dragEnd(let point):
            guard lastDrag != nil else { return false }
            let position = location(point)
            mouse(.leftMouseDragged, at: position, clicks: 1)
            lastDrag = position
            releaseDrag()
        case .scroll(let point, let horizontal, let vertical):
            let position = location(point)
            mouse(.mouseMoved, at: position)
            let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                                wheel1: vertical, wheel2: horizontal, wheel3: 0)
            event?.location = position
            event?.post(tap: .cgSessionEventTap)
        case .type(let text):
            for character in text {
                if character == "\n" || character == "\r\n" { key(kVK_Return) }
                else if character == "\t" { key(kVK_Tab) }
                else { key(0, text: Array(String(character).utf16)) }
            }
        case .key(let value):
            switch value {
            case .escape: key(kVK_Escape)
            case .tab: key(kVK_Tab)
            case .delete: key(kVK_Delete)
            case .enter: key(kVK_Return)
            case .left: key(kVK_LeftArrow)
            case .right: key(kVK_RightArrow)
            case .up: key(kVK_UpArrow)
            case .down: key(kVK_DownArrow)
            case .undo: key(kVK_ANSI_Z, flags: .maskCommand)
            case .copy: key(kVK_ANSI_C, flags: .maskCommand)
            case .paste: key(kVK_ANSI_V, flags: .maskCommand)
            case .selectAll: key(kVK_ANSI_A, flags: .maskCommand)
            }
        }
        return true
    }

    func releaseDrag() {
        if let lastDrag { mouse(.leftMouseUp, at: lastDrag, clicks: 1) }
        lastDrag = nil
        dragTimer.schedule(deadline: .distantFuture)
    }

    private func updateDrag(_ position: CGPoint) {
        lastDrag = position
        dragTimer.schedule(deadline: .now() + 4)
    }

    private func mouse(_ type: CGEventType, at position: CGPoint, button: CGMouseButton = .left, clicks: Int64 = 0) {
        let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: position, mouseButton: button)
        event?.setIntegerValueField(.mouseEventClickState, value: clicks)
        event?.post(tap: .cgSessionEventTap)
    }

    private func key(_ keyCode: Int, flags: CGEventFlags = [], text: [UniChar] = []) {
        for pressed in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: pressed) else { continue }
            event.flags = flags
            if !text.isEmpty { event.keyboardSetUnicodeString(stringLength: text.count, unicodeString: text) }
            event.post(tap: .cgSessionEventTap)
        }
    }
}
