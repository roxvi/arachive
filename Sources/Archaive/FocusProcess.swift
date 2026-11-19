import Darwin
import Foundation

struct FocusProcessID: Codable, Hashable {
    let pid: pid_t
    let seconds: UInt64
    let microseconds: UInt64

    init(_ info: proc_bsdinfo) {
        pid = pid_t(info.pbi_pid)
        seconds = info.pbi_start_tvsec
        microseconds = info.pbi_start_tvusec
    }

    static func read(_ pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard geteuid() != 0, pid > 1, proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
              info.pbi_uid == geteuid(), info.pbi_ruid == getuid() else { return nil }
        return info
    }
}

struct FocusProcess {
    let id: FocusProcessID
    let parent: pid_t
    let app: String?
    var isMain = false

    static func bundlePath(for executable: String) -> String? {
        guard executable.hasPrefix("/"), let end = executable.range(of: ".app/Contents/", options: .caseInsensitive) else { return nil }
        let suffix = executable.index(end.lowerBound, offsetBy: 4)
        let path = String(executable[..<suffix])
        let dataPrefix = "/System/Volumes/Data"
        return path.hasPrefix(dataPrefix + "/") ? String(path.dropFirst(dataPrefix.count)) : path
    }

    static func canPause(_ path: String, own: String) -> Bool {
        guard path != own, !path.hasPrefix("/Library/"), !path.hasPrefix("/System/Volumes/") else { return false }
        guard path.hasPrefix("/System/") else { return true }
        // Leave Finder, system services, settings and recovery tools available.
        return path.hasPrefix("/System/Applications/") && !path.hasPrefix("/System/Applications/Utilities/")
            && path != "/System/Applications/System Settings.app"
    }

    static func snapshot() -> [FocusProcess] {
        let capacity = Int(proc_listallpids(nil, 0)) + 128
        guard capacity > 128 else { return [] }
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = Int(pids.withUnsafeMutableBytes {
            proc_listallpids($0.baseAddress, Int32($0.count))
        })
        guard count > 0 else { return [] }
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        var executables: [String: String] = [:]
        return pids.prefix(count).compactMap { pid in
            guard let info = FocusProcessID.read(pid) else { return nil }
            let size = proc_pidpath(pid, &buffer, UInt32(buffer.count))
            let path = size > 0 ? String(cString: buffer) : ""
            let app = bundlePath(for: path)
            var process = FocusProcess(id: FocusProcessID(info), parent: pid_t(info.pbi_ppid), app: app)
            if let app, let relative = path.range(of: ".app/Contents/", options: .caseInsensitive) {
                let name = executables[app] ?? Bundle(path: app)?.executableURL?.lastPathComponent ?? ""
                executables[app] = name
                process.isMain = !name.isEmpty && path[relative.upperBound...] == "MacOS/" + name
            }
            return process
        }
    }
}

enum NewFocusApps: String, CaseIterable {
    case keepRunning, pause

    var title: String {
        switch self {
        case .keepRunning: return "Keep running"
        case .pause: return "Pause automatically"
        }
    }
}

struct FocusPolicy {
    let initial: Set<FocusProcessID>

    func targets(in processes: [FocusProcess], keeping allowed: Set<String>, newApps: NewFocusApps, own: String) -> [FocusProcess] {
        let byPID = Dictionary(processes.map { ($0.id.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let originalApps = Set(processes.compactMap { initial.contains($0.id) ? $0.app : nil })
        let newMainApps = Set(processes.compactMap { $0.isMain && !initial.contains($0.id) ? $0.app : nil })
        return processes.filter { process in
            guard let app = process.app, FocusProcess.canPause(app, own: own), process.id.pid != getpid(),
                  newApps == .pause || (originalApps.contains(app) && !newMainApps.contains(app)) else { return false }
            var current: FocusProcess? = process
            while let ancestor = current {
                if let owner = ancestor.app, allowed.contains(owner) || owner == own { return false }
                guard let parent = byPID[ancestor.parent],
                      (parent.id.seconds, parent.id.microseconds) < (ancestor.id.seconds, ancestor.id.microseconds) else { break }
                current = parent
            }
            return true
        }
    }
}

struct FocusPauseReply: Codable {
    let paused: Set<FocusProcessID>
    let failed: Int
}

/// The helper owns the pause records. A closed pipe also releases them if the UI crashes or is force quit.
enum FocusPauseWorker {
    static let argument = "--focus-pause-worker"

    static func run() {
        let output = FileHandle.standardOutput
        _ = fcntl(output.fileDescriptor, F_SETNOSIGPIPE, 1)
        var paused = Set<FocusProcessID>()
        defer {
            for process in paused { _ = resume(process) }
        }
        while let line = readLine() {
            guard let desired = try? JSONDecoder().decode(Set<FocusProcessID>.self, from: Data(line.utf8)) else { break }
            var failed = 0
            for process in paused.subtracting(desired) {
                if resume(process) { paused.remove(process) }
                else { failed += 1 }
            }
            for process in desired {
                guard process.pid != getpid(), let info = matchingInfo(process) else {
                    paused.remove(process)
                    continue
                }
                if info.pbi_status == SSTOP { continue }
                guard info.pbi_status != SZOMB, info.pbi_flags & UInt32(PROC_FLAG_TRACED) == 0,
                      kill(process.pid, SIGSTOP) == 0 else {
                    failed += 1
                    continue
                }
                paused.insert(process)
            }
            do {
                let reply = try JSONEncoder().encode(FocusPauseReply(paused: paused, failed: failed))
                try output.write(contentsOf: reply + Data([10]))
            } catch { break }
        }
    }

    private static func matchingInfo(_ process: FocusProcessID) -> proc_bsdinfo? {
        guard let info = FocusProcessID.read(process.pid), FocusProcessID(info) == process else { return nil }
        return info
    }

    private static func resume(_ process: FocusProcessID) -> Bool {
        guard matchingInfo(process) != nil else { return true }
        return kill(process.pid, SIGCONT) == 0 || errno == ESRCH
    }
}

final class FocusPauseClient {
    private let worker = Process()
    private let input = Pipe()
    private let output = Pipe()

    init(executable: URL) throws {
        worker.executableURL = executable
        worker.arguments = [FocusPauseWorker.argument]
        worker.standardInput = input
        worker.standardOutput = output
        let descriptor = input.fileHandleForWriting.fileDescriptor
        _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
        _ = fcntl(descriptor, F_SETNOSIGPIPE, 1)
        try worker.run()
    }

    deinit { try? input.fileHandleForWriting.close() }

    func apply(_ desired: Set<FocusProcessID>) throws -> FocusPauseReply {
        let request = try JSONEncoder().encode(desired)
        try input.fileHandleForWriting.write(contentsOf: request + Data([10]))
        var reply = Data()
        let deadline = ProcessInfo.processInfo.systemUptime + 1
        repeat {
            var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let remaining = Int32(max(0, (deadline - ProcessInfo.processInfo.systemUptime) * 1000))
            guard remaining > 0, poll(&descriptor, 1, remaining) == 1 else {
                throw CocoaError(.fileReadUnknown)
            }
            var buffer = [UInt8](repeating: 0, count: 4096)
            let count = Darwin.read(descriptor.fd, &buffer, buffer.count)
            guard count > 0 else { throw CocoaError(.fileReadUnknown) }
            reply.append(contentsOf: buffer.prefix(count))
        } while reply.last != 10
        return try JSONDecoder().decode(FocusPauseReply.self, from: reply.dropLast())
    }
}
