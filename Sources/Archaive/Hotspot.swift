import Foundation
import Network
import CoreWLAN

final class Hotspot {
    var onStatus: ((String) -> Void)?
    private let queue = DispatchQueue(label: "Archaive.Hotspot")
    private let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
    private var connected = false
    private var observedPath = false
    private var policy = ReconnectPolicy()
    private var timer: DispatchSourceTimer?

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.connected = path.status == .satisfied
            self?.observedPath = true
        }
        monitor.start(queue: queue)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 3)
        timer.setEventHandler { [weak self] in self?.tick() }
        self.timer = timer
        timer.resume()
    }

    private func report(_ value: String) { DispatchQueue.main.async { self.onStatus?(value) } }

    private func tick() {
        let defaults = UserDefaults.standard
        let enabled = defaults.bool(forKey: "hotspotEnabled")
        let name = defaults.string(forKey: "hotspotName") ?? ""
        guard observedPath else { return }
        let interface = CWWiFiClient.shared().interface()
        let wifiOn = interface?.powerOn() ?? false
        guard policy.shouldAttempt(now: Date(), enabled: enabled, wifiOn: wifiOn, connected: connected, configured: !name.isEmpty) else {
            if !enabled { report("Hotspot fallback off") }
            else if name.isEmpty { report("Set your hotspot name") }
            else if !wifiOn { report("Wi-Fi is switched off") }
            else if connected { report("Wi-Fi connected") }
            else if policy.lastAttempt == nil { report("Waiting for Wi-Fi…") }
            return
        }
        guard let device = interface?.interfaceName else { report("Wi-Fi interface unavailable"); return }
        report("Connecting to \(name)…")
        var arguments = ["-setairportnetwork", device, name]
        var input: Data?
        if defaults.bool(forKey: "hotspotUseCustomPassword") {
            do {
                guard let password = try HotspotPassword.read(for: name), System.customPasswordError(password) == nil else {
                    report("Custom password missing — open Hotspot Settings")
                    return
                }
                // networksetup accepts '-' to read a password from stdin, keeping it out of process arguments.
                arguments.append("-")
                input = Data((password + "\n").utf8)
            } catch {
                report("Keychain unavailable — open Hotspot Settings")
                return
            }
        }
        let result = System.run("/usr/sbin/networksetup", arguments, input: input)
        if result.status != 0 || !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            report("Hotspot unavailable — retrying in 45s")
        } else { report("Hotspot join requested") }
    }
}
