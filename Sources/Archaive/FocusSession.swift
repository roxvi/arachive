import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FocusApp: Identifiable, Equatable {
    let id: String
    let name: String
    let running: Bool
    let paused: Bool
}

final class FocusSession: ObservableObject {
    @Published private(set) var apps: [FocusApp] = []
    @Published private(set) var allowed: Set<String>
    @Published private(set) var newApps: NewFocusApps
    @Published private(set) var active = false
    @Published private(set) var message: String?

    private let defaults: UserDefaults
    private let own = Bundle.main.bundleURL.resolvingSymlinksInPath().path
    private var policy: FocusPolicy?
    private var client: FocusPauseClient?
    private var paused: Set<FocusProcessID> = []
    private var ending = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        allowed = Set(defaults.stringArray(forKey: "focusAllowedApps") ?? [])
        newApps = defaults.string(forKey: "focusNewApps").flatMap(NewFocusApps.init(rawValue:)) ?? .keepRunning
    }

    func setAllowed(_ path: String, _ keep: Bool) {
        if keep { allowed.insert(path) }
        else { allowed.remove(path) }
        defaults.set(allowed.sorted(), forKey: "focusAllowedApps")
        refresh()
    }

    func setNewApps(_ value: NewFocusApps) {
        newApps = value
        defaults.set(value.rawValue, forKey: "focusNewApps")
        if active { refresh() }
    }

    func addApps(in window: NSWindow) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.prompt = "Keep Running"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.beginSheetModal(for: window) { [weak self] result in
            guard let self, result == .OK else { return }
            let paths = panel.urls.map { $0.resolvingSymlinksInPath().path }
            self.allowed.formUnion(paths.filter { FocusProcess.canPause($0, own: self.own) })
            self.defaults.set(self.allowed.sorted(), forKey: "focusAllowedApps")
            self.refresh()
            if paths.contains(where: { !FocusProcess.canPause($0, own: self.own) }) {
                self.message = "Protected apps already stay running."
            }
        }
    }

    func start() {
        guard !active, !allowed.isEmpty, let executable = Bundle.main.executableURL else { return }
        do {
            client = try FocusPauseClient(executable: executable)
            let processes = FocusProcess.snapshot()
            policy = FocusPolicy(initial: Set(processes.map(\.id)))
            active = true
            update(processes)
        } catch {
            message = "Couldn’t start Focus. Try starting a new session."
        }
    }

    @discardableResult
    func stop() -> Bool {
        guard active else { return true }
        ending = true
        refresh()
        return !active
    }

    func refresh() { update(FocusProcess.snapshot()) }

    private func update(_ processes: [FocusProcess]) {
        if let client, let policy {
            let targets = ending ? [] : policy.targets(in: processes, keeping: allowed, newApps: newApps, own: own)
            do {
                let reply = try client.apply(Set(targets.map(\.id)))
                paused = reply.paused
                updateMessage(reply.failed == 0 ? nil : ending
                    ? "Some apps couldn’t resume. Archaive is retrying."
                    : "Some processes couldn’t be paused or resumed.")
                if ending && paused.isEmpty { finish() }
            } catch {
                finish()
                updateMessage("Focus was interrupted. The background helper resumes apps when its connection closes.")
            }
        }

        let running = Set(processes.compactMap(\.app).filter { FocusProcess.canPause($0, own: own) })
        let pausedApps = Set(processes.filter { paused.contains($0.id) }.compactMap(\.app))
        let previous = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0.name) })
        let list = running.union(allowed).map { path in
            FocusApp(id: path, name: previous[path] ?? FileManager.default.displayName(atPath: path),
                     running: running.contains(path), paused: pausedApps.contains(path))
        }.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
        if apps != list { apps = list }
    }

    private func updateMessage(_ value: String?) {
        if message != value { message = value }
    }

    private func finish() {
        client = nil
        policy = nil
        paused = []
        ending = false
        active = false
    }
}
