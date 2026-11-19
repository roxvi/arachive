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
    @Published private(set) var enabled: Bool
    @Published private(set) var closedLidOnly: Bool
    @Published private(set) var lidClosed: Bool?
    @Published private(set) var active = false
    @Published private(set) var message: String?

    private let defaults: UserDefaults
    private let processes: () -> [FocusProcess]
    private let own = Bundle.main.bundleURL.resolvingSymlinksInPath().path
    private var policy: FocusPolicy?
    private var client: FocusPauseClient?
    private var paused: Set<FocusProcessID> = []
    private var awake = false
    private var interrupted = false

    init(defaults: UserDefaults = .standard, processes: @escaping () -> [FocusProcess] = FocusProcess.snapshot) {
        self.defaults = defaults
        self.processes = processes
        enabled = defaults.bool(forKey: "focusEnabled")
        closedLidOnly = defaults.bool(forKey: "focusClosedLidOnly")
        allowed = Set(defaults.stringArray(forKey: "focusAllowedApps") ?? [])
        newApps = defaults.string(forKey: "focusNewApps").flatMap(NewFocusApps.init(rawValue:)) ?? .keepRunning
    }

    func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        enabled = value
        defaults.set(value, forKey: "focusEnabled")
        reconcile()
    }

    func setKeepAwake(_ value: Bool) {
        guard awake != value else { return }
        awake = value
        reconcile()
    }

    func setClosedLidOnly(_ value: Bool) {
        guard closedLidOnly != value else { return }
        closedLidOnly = value
        defaults.set(value, forKey: "focusClosedLidOnly")
        reconcile()
    }

    func setLidClosed(_ value: Bool?) {
        guard lidClosed != value else { return }
        lidClosed = value
        if closedLidOnly { reconcile() }
    }

    private var shouldPause: Bool {
        enabled && awake && !allowed.isEmpty && (!closedLidOnly || lidClosed == true)
    }

    private func reconcile() {
        if active || shouldPause { refresh() }
        else if interrupted {
            interrupted = false
            updateMessage(nil)
        }
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

    func refresh() {
        let processes = self.processes()
        if !shouldPause && interrupted {
            interrupted = false
            updateMessage(nil)
        }
        if shouldPause && !active && !interrupted {
            start(processes)
        }
        if let client, let policy {
            let targets = shouldPause ? policy.targets(in: processes, keeping: allowed, newApps: newApps, own: own) : []
            do {
                let reply = try client.apply(Set(targets.map(\.id)))
                paused = reply.paused
                updateMessage(reply.failed == 0 ? nil : shouldPause
                    ? "Some processes couldn’t be paused or resumed."
                    : "Some apps couldn’t resume. Archaive is retrying.")
                if !shouldPause && paused.isEmpty { finish() }
            } catch {
                finish()
                interrupted = shouldPause
                updateMessage("Focus was interrupted. Turn Focus off and on to retry.")
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

    private func start(_ processes: [FocusProcess]) {
        do {
            guard let executable = Bundle.main.executableURL else { throw CocoaError(.fileNoSuchFile) }
            client = try FocusPauseClient(executable: executable)
            policy = FocusPolicy(initial: Set(processes.map(\.id)))
            active = true
        } catch {
            interrupted = true
            updateMessage("Couldn’t start Focus. Turn Focus off and on to retry.")
        }
    }

    private func updateMessage(_ value: String?) {
        if message != value { message = value }
    }

    private func finish() {
        client = nil
        policy = nil
        paused = []
        active = false
    }
}
