import Foundation
import CoreGraphics
import Darwin

// DisplayServices is private: resolve it at runtime and never fall back to display sleep.
final class DisplayBrightness {
    typealias Get = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    typealias Set = @convention(c) (UInt32, Float) -> Int32
    private let library: UnsafeMutableRawPointer?
    private let get: Get?
    private let set: Set?
    private var session = BrightnessSession()
    private var available: [UInt32] = []

    init() {
        library = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
        get = library.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: Get.self) }
        set = library.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: Set.self) }
    }

    deinit { if let library { dlclose(library) } }

    func rememberDisplays() {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success else { return }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return }
        available = Array(displays.prefix(Int(count)))
    }

    func dim() -> Bool {
        guard let get, let set else { return false }
        return session.dim(displays: available, read: { id in
            var value: Float = 0
            return get(id, &value) == 0 ? value : nil
        }, write: { set($0, $1) == 0 })
    }

    @discardableResult func restore() -> Bool {
        guard let set else { return session.saved.isEmpty }
        return session.restore { set($0, $1) == 0 }
    }
}

struct BrightnessSession {
    private(set) var saved: [UInt32: Float] = [:]

    mutating func dim(displays: [UInt32], read: (UInt32) -> Float?, write: (UInt32, Float) -> Bool) -> Bool {
        var changed = false
        for id in displays {
            guard let value = read(id), value.isFinite, (0...1).contains(value) else { continue }
            if saved[id] == nil { saved[id] = value }
            if write(id, 0) { changed = true }
        }
        return changed
    }

    mutating func restore(write: (UInt32, Float) -> Bool) -> Bool {
        for (id, value) in saved where write(id, value) { saved.removeValue(forKey: id) }
        return saved.isEmpty
    }
}
