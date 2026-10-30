import Foundation
import IOKit

struct CommandResult {
    let status: Int32
    let output: String
}

enum System {
    static func run(_ path: String, _ args: [String], input: Data? = nil) -> CommandResult {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = pipe
        let inputPipe = input.map { _ in Pipe() }
        if let inputPipe { process.standardInput = inputPipe }
        do {
            try process.run()
            if let inputPipe, let input {
                inputPipe.fileHandleForWriting.write(input)
                inputPipe.fileHandleForWriting.closeFile()
            }
            let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 90, execute: deadline)
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            deadline.cancel()
            return CommandResult(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
        } catch { return CommandResult(status: -1, output: error.localizedDescription) }
    }

    static func customPasswordError(_ password: String) -> String? {
        if password.isEmpty { return "Enter a custom password, or turn off Use Custom Password." }
        if password.utf8.count > 1024 || password.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\0" }) {
            return "Enter a password without line breaks or null characters (up to 1,024 bytes)."
        }
        return nil
    }

    static func hotspotNameError(_ name: String) -> String? {
        if name.isEmpty { return "Enter your hotspot’s Wi-Fi name." }
        if name.contains("\0") { return "Wi-Fi names cannot contain a null character." }
        if name.utf8.count > 32 { return "This name is \(name.utf8.count) bytes. Wi-Fi allows 32 bytes; emoji can use several bytes each. Use the exact name shown in Wi-Fi settings." }
        return nil
    }

    static func sleepDisabled() -> Bool? {
        let result = run("/usr/bin/pmset", ["-g"])
        guard result.status == 0 else { return nil }
        return parseSleepDisabled(result.output)
    }

    static func parseSleepDisabled(_ output: String) -> Bool? {
        for line in output.split(separator: "\n") {
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            if fields.first == "SleepDisabled", fields.count == 2, let value = Int(fields[1]) { return value != 0 }
        }
        return nil
    }

    static func setSleepDisabled(_ value: Bool) -> CommandResult {
        guard SleepAccess.isInstalled else {
            return CommandResult(status: 1, output: "Choose Set Up Password-Free Toggles in the menu first. Administrator approval is needed once, not for each toggle.")
        }
        let result = run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", value ? "1" : "0"])
        guard result.status == 0 else {
            return CommandResult(status: result.status, output: "Password-free access was denied. Check setup in the Archaive menu. " + result.output)
        }
        return result
    }

    static func lidClosed() -> Bool? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return (IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.boolValue
    }
}

struct ReconnectPolicy {
    var disconnectedSince: Date?
    var lastAttempt: Date?

    mutating func shouldAttempt(now: Date, enabled: Bool, wifiOn: Bool, connected: Bool, configured: Bool) -> Bool {
        guard enabled, wifiOn, configured, !connected else {
            disconnectedSince = nil
            return false
        }
        guard let since = disconnectedSince else { disconnectedSince = now; return false }
        guard now.timeIntervalSince(since) >= 12,
              lastAttempt.map({ now.timeIntervalSince($0) >= 45 }) ?? true else { return false }
        lastAttempt = now
        return true
    }
}
