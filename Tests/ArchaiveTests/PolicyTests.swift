import Foundation
import AppKit

func XCTAssertEqual<T: Equatable>(_ actual: T, _ expected: T) { precondition(actual == expected) }
func XCTAssertNil<T>(_ value: T?) { precondition(value == nil) }
func XCTAssertTrue(_ value: Bool) { precondition(value) }
func XCTAssertFalse(_ value: Bool) { precondition(!value) }

@main
struct PolicyTests {
    static func main() {
        if CommandLine.arguments.dropFirst().first == FocusPauseWorker.argument {
            FocusPauseWorker.run()
            return
        }
        let tests = PolicyTests()
        tests.testPowerStateParsingRejectsMissingOrMalformedState()
        tests.testDisconnectGraceAndRetryBackoff()
        tests.testReconnectResetsGraceAndNeverOverridesWifiOff()
        tests.testDisabledOrUnconfiguredNeverJoins()
        tests.testEmojiNamesAndProcessArguments()
        tests.testBrightnessRestoreAndFailure()
        tests.testCustomPasswordTransport()
        tests.testOnboardingNavigationAndDemoIsolation()
        tests.testSleepAccessRuleAndInstaller()
        tests.testShortcutPreferences()
        tests.testShortcutRecordingLifecycle()
        tests.testShortcutResponderRouting()
        tests.testPhoneSharingSessionIsolation()
        tests.testIPhonePairingAddresses()
        try! tests.testPhoneControlAuthentication()
        tests.testFocusPolicy()
        try! tests.testFocusPauseLifecycle()
        try! tests.testFocusFollowsKeepAwake()
        print("18 regression tests passed")
    }
    func testFocusPolicy() {
        func process(_ pid: Int32, _ parent: Int32 = 1, _ app: String? = nil, born: UInt64? = nil) -> FocusProcess {
            var info = proc_bsdinfo()
            info.pbi_pid = UInt32(pid)
            info.pbi_start_tvsec = born ?? UInt64(pid)
            return FocusProcess(id: FocusProcessID(info), parent: parent, app: app)
        }
        let editor = "/Applications/Editor.app"
        let other = "/Applications/Browser.app"
        let own = "/Applications/Archaive.app"
        let kept = process(10, 1, editor)
        let paused = process(11, 1, other)
        let policy = FocusPolicy(initial: [kept.id, paused.id])
        let list = [
            kept, paused, process(12, 1, other), process(13, 1, "/Applications/New.app"),
            process(14, 10), process(15, 14, "/Applications/Related.app"),
            process(16, 1, "/System/Library/CoreServices/Finder.app"),
            process(17, 1, "/System/Applications/Utilities/Activity Monitor.app"),
            process(18, 1, "/System/Applications/System Settings.app"),
            process(19, 1, own), process(20, 1)
        ]
        XCTAssertEqual(policy.targets(in: list, keeping: [editor], newApps: .keepRunning, own: own).map(\.id.pid), [11, 12])
        XCTAssertEqual(policy.targets(in: list, keeping: [editor], newApps: .pause, own: own).map(\.id.pid), [11, 12, 13])
        // A relaunched app and a recycled PID are fresh processes.
        XCTAssertTrue(policy.targets(in: [process(11, 1, other, born: 99)],
                                     keeping: [], newApps: .keepRunning, own: own).isEmpty)
        XCTAssertEqual(FocusProcess.bundlePath(for: editor + "/Contents/Frameworks/Helper.app/Contents/MacOS/Helper"), editor)
        XCTAssertEqual(FocusProcess.bundlePath(for: "/System/Volumes/Data" + editor + "/Contents/MacOS/Editor"), editor)
        XCTAssertNil(FocusProcess.bundlePath(for: "/usr/libexec/networkd"))
    }

    func testFocusPauseLifecycle() throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["60"]
        try child.run()
        let pid = child.processIdentifier
        defer {
            kill(pid, SIGKILL)
            child.waitUntilExit()
        }
        let identity = FocusProcessID(FocusProcessID.read(pid)!)
        var client: FocusPauseClient? = try FocusPauseClient(executable: Bundle.main.executableURL!)
        XCTAssertEqual(try client!.apply([identity]).paused, [identity])
        expectStopped(pid, true)
        XCTAssertTrue(try client!.apply([]).paused.isEmpty)
        expectStopped(pid, false)

        kill(pid, SIGSTOP)
        expectStopped(pid, true)
        XCTAssertTrue(try client!.apply([identity]).paused.isEmpty)
        XCTAssertTrue(try client!.apply([]).paused.isEmpty)
        expectStopped(pid, true)
        kill(pid, SIGCONT)
        expectStopped(pid, false)

        XCTAssertEqual(try client!.apply([identity]).paused, [identity])
        expectStopped(pid, true)
        client = nil
        expectStopped(pid, false)
    }

    func testFocusFollowsKeepAwake() throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["60"]
        try child.run()
        let pid = child.processIdentifier
        let suite = "Archaive.FocusTest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            kill(pid, SIGKILL)
            child.waitUntilExit()
            defaults.removePersistentDomain(forName: suite)
        }
        let target = FocusProcess(id: FocusProcessID(FocusProcessID.read(pid)!), parent: 1, app: "/Applications/Other.app")
        let focus = FocusSession(defaults: defaults, processes: { [target] })
        let allowed = "/Applications/Editor.app"
        XCTAssertFalse(focus.enabled)
        focus.setAllowed(allowed, true)
        focus.setEnabled(true)
        XCTAssertFalse(focus.active)
        expectStopped(pid, false)

        focus.setKeepAwake(true)
        XCTAssertTrue(focus.active)
        expectStopped(pid, true)
        focus.setKeepAwake(false)
        XCTAssertFalse(focus.active)
        XCTAssertTrue(focus.enabled)
        expectStopped(pid, false)

        focus.setKeepAwake(true)
        expectStopped(pid, true)
        focus.setAllowed(allowed, false)
        XCTAssertFalse(focus.active)
        expectStopped(pid, false)
        focus.setAllowed(allowed, true)
        expectStopped(pid, true)
        focus.setEnabled(false)
        XCTAssertFalse(focus.active)
        expectStopped(pid, false)
        focus.setKeepAwake(false)
        focus.setKeepAwake(true)
        XCTAssertFalse(focus.active)
        XCTAssertFalse(defaults.bool(forKey: "focusEnabled"))

        XCTAssertFalse(focus.closedLidOnly)
        focus.setClosedLidOnly(true)
        focus.setEnabled(true)
        XCTAssertFalse(focus.active) // An unavailable lid reading leaves apps running.
        focus.setLidClosed(false)
        XCTAssertFalse(focus.active)
        expectStopped(pid, false)

        focus.setLidClosed(true)
        XCTAssertTrue(focus.active)
        expectStopped(pid, true)
        focus.setLidClosed(false)
        XCTAssertFalse(focus.active)
        expectStopped(pid, false)

        focus.setLidClosed(true)
        expectStopped(pid, true)
        focus.setLidClosed(nil)
        XCTAssertFalse(focus.active)
        expectStopped(pid, false)

        focus.setKeepAwake(false)
        focus.setLidClosed(true)
        XCTAssertFalse(focus.active)
        focus.setKeepAwake(true)
        expectStopped(pid, true)
        focus.setKeepAwake(false)
        expectStopped(pid, false)
        focus.setLidClosed(false)
        focus.setKeepAwake(true)
        expectStopped(pid, false)
        XCTAssertTrue(FocusSession(defaults: defaults).closedLidOnly)
        focus.setClosedLidOnly(false)
        expectStopped(pid, true)
        focus.setClosedLidOnly(true)
        expectStopped(pid, false)
    }

    private func expectStopped(_ pid: pid_t, _ stopped: Bool) {
        for _ in 0..<100 {
            if let info = FocusProcessID.read(pid), (info.pbi_status == SSTOP) == stopped { return }
            usleep(10_000)
        }
        preconditionFailure("Focus test process did not change stop state")
    }

    func testIPhonePairingAddresses() {
        let token = "0123456789abcdef0123456789ABCDEF"
        for host in ["10.0.0.2", "172.16.0.1", "172.31.255.254", "192.168.1.20", "169.254.2.1"] {
            let link = "http://\(host):43210/\(token)/"
            XCTAssertEqual(ShareAddress(" \(link)\n")?.frameURL.absoluteString, link + "frame")
        }
        for host in ["example.com", "127.0.0.1", "0.0.0.0", "192.168.1.999", "192.168.01.1", "192.168.1", "172.15.0.1", "172.32.0.1", "8.8.8.8"] {
            XCTAssertNil(ShareAddress("http://\(host):43210/\(token)/"))
        }
        let base = "http://192.168.1.20:43210/\(token)/"
        let key = PhoneControl.PairingKey()
        let controlLink = "archaive-control" + base.dropFirst(4) + "#" + key.code
        let pairing = ShareAddress(controlLink)
        XCTAssertEqual(pairing?.controlKey, key)
        XCTAssertEqual(pairing?.frameURL.absoluteString, base + "frame")
        XCTAssertEqual(pairing?.controlURL.absoluteString, base + "control")
        XCTAssertNil(ShareAddress(base)?.controlKey)
        XCTAssertNil(ShareAddress(controlLink + "="))
        XCTAssertNil(ShareAddress(controlLink.replacingOccurrences(of: "192.168.1.20", with: "8.8.8.8")))
        for invalid in [base + "frame", base + "?query=1", base + "#fragment",
                        base.replacingOccurrences(of: "http:", with: "https:"),
                        base.replacingOccurrences(of: token, with: "wrong"),
                        base.replacingOccurrences(of: "43210", with: "0"),
                        base.replacingOccurrences(of: "43210", with: "65536"),
                        base.replacingOccurrences(of: ":43210", with: ""),
                        base.replacingOccurrences(of: "192.168", with: "user@192.168")] {
            XCTAssertNil(ShareAddress(invalid))
        }
    }

    func testPhoneSharingSessionIsolation() {
        func route(_ request: String, token: String = "current") -> PhoneShareHTTP.Route {
            PhoneShareHTTP.route(Data(request.utf8), token: token)
        }
        XCTAssertEqual(route("GET /current/ HTTP/1.1\r\nHost: mac\r\n\r\n"), .page)
        XCTAssertEqual(route("GET /current/frame HTTP/1.1\r\n\r\n"), .frame)
        for path in ["/", "/old/frame", "/current/frame?token=old", "/current/../frame", "/current/frame/", "http://mac/current/frame"] {
            XCTAssertEqual(route("GET \(path) HTTP/1.1\r\n\r\n"), .missing)
        }
        XCTAssertEqual(route("POST /current/frame HTTP/1.1\r\n\r\n"), .missing)
        XCTAssertEqual(route("GET /current/frame HTTP/1.1\r\n\r\n", token: "next-session"), .missing)
        XCTAssertEqual(route("GET  /current/frame HTTP/1.1\r\n\r\n"), .missing)
        XCTAssertEqual(route("GET /current/frame HTTP/9.9\r\n\r\n"), .missing)
        XCTAssertEqual(PhoneShareHTTP.route(Data([0xff]), token: "current"), .missing)
        let post = "POST /current/control HTTP/1.1\r\nContent-Type: application/octet-stream\r\n"
        let length = "Content-Length: 28\r\n"
        let header = Data((post + length + "\r\n").utf8)
        let binaryBody = Data(repeating: 0xff, count: 28)
        XCTAssertEqual(PhoneShareHTTP.route(header + binaryBody, token: "current"), .control(length: 28))
        XCTAssertEqual(PhoneShareHTTP.route(header + binaryBody, token: "different"), .missing)
        XCTAssertEqual(route("GET /current/control HTTP/1.1\r\n\r\n"), .missing)
        XCTAssertEqual(route(post + length + length + "\r\n"), .missing)
        XCTAssertEqual(route(post + "Content-Length: 4097\r\n\r\n"), .missing)
        XCTAssertEqual(route(post + length + "Transfer-Encoding: chunked\r\n\r\n"), .missing)
        XCTAssertEqual(route(post + "\r\n"), .missing)
    }

    func testPhoneControlAuthentication() throws {
        let key = PhoneControl.PairingKey()
        var receiver = PhoneControl.Receiver(key: key)
        let point = PhoneControl.Point(x: 0.5, y: 1)
        let command = PhoneControl.Command.click(point)
        let first = try PhoneControl.seal(command, sequence: 1, epoch: 10, key: key)
        let forged = try PhoneControl.seal(.key(.delete), sequence: 2, epoch: 10, key: .init())
        let invalid = try PhoneControl.seal(.click(.init(x: -1, y: 0)), sequence: 2, epoch: 10, key: key)
        XCTAssertNil(receiver.accept(forged, epoch: 10))
        XCTAssertNil(receiver.accept(invalid, epoch: 10))
        XCTAssertNil(receiver.accept(first, epoch: 9))
        XCTAssertNil(receiver.accept(first, epoch: 12))
        XCTAssertNil(receiver.accept(first + Data([1]), epoch: 10))
        XCTAssertEqual(receiver.sequence, 0)
        XCTAssertEqual(receiver.accept(first, epoch: 11), command)
        XCTAssertNil(receiver.accept(first, epoch: 11))
        let text = PhoneControl.Command.type("Archaive 👋")
        let second = try PhoneControl.seal(text, sequence: 2, epoch: 11, key: key)
        XCTAssertEqual(receiver.accept(second, epoch: 11), text)

        let frame = Data([1, 2, 3])
        let headers = receiver.headers(for: frame, epoch: 11)
        let proofLine = headers.components(separatedBy: "\r\n").first { $0.hasPrefix(PhoneControl.proofHeader) }!
        let proof = String(proofLine.dropFirst(PhoneControl.proofHeader.count + 2))
        XCTAssertTrue(PhoneControl.verifyFrame(frame, proof: proof, sequence: 2, epoch: 11, key: key))
        XCTAssertFalse(PhoneControl.verifyFrame(frame + Data([4]), proof: proof, sequence: 2, epoch: 11, key: key))
        XCTAssertFalse(PhoneControl.verifyFrame(frame, proof: proof, sequence: 3, epoch: 11, key: key))
        XCTAssertFalse(PhoneControl.verifyFrame(frame, proof: proof, sequence: 2, epoch: 12, key: key))
        XCTAssertFalse(PhoneControl.verifyFrame(frame, proof: proof, sequence: 2, epoch: 11, key: .init()))
    }

    func testShortcutRecordingLifecycle() {
        _ = NSApplication.shared
        let recorder = ShortcutRecordButton()
        var changes: [Bool] = []
        var saved: [Shortcut] = []
        recorder.recordingChanged = { changes.append($0) }
        recorder.save = { saved.append($0); return nil }
        recorder.startRecording()
        recorder.updateModifiers([.command, .option])
        XCTAssertEqual(recorder.liveSymbols, ["⌥", "⌘", "…"])
        recorder.capture(keyCode: 0, flags: [])
        XCTAssertTrue(recorder.recording)
        XCTAssertTrue(saved.isEmpty)
        recorder.capture(keyCode: 0, flags: [.command], repeating: true)
        XCTAssertTrue(saved.isEmpty)
        recorder.capture(keyCode: 0, flags: [.command])
        XCTAssertEqual(saved, [Shortcut(keyCode: 0, modifiers: 256)])
        XCTAssertFalse(recorder.recording)
        XCTAssertEqual(changes, [true, false])
        recorder.startRecording()
        recorder.capture(keyCode: 53, flags: [])
        XCTAssertEqual(saved.count, 1)
        XCTAssertFalse(recorder.recording)
        recorder.save = { _ in "Already in use" }
        recorder.startRecording()
        recorder.capture(keyCode: 40, flags: [.control, .option, .command])
        XCTAssertTrue(recorder.recording)
        XCTAssertEqual(recorder.shortcut.label, "⌘A")
        recorder.stopRecording()
        XCTAssertEqual(changes, [true, false, true, false, true, false])
    }

    func testShortcutResponderRouting() {
        _ = NSApplication.shared
        let recorder = ShortcutRecordButton()
        var saved: Shortcut?
        recorder.save = { saved = $0; return nil }
        recorder.startRecording()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 250, height: 50), styleMask: .titled, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = recorder
        XCTAssertTrue(window.makeFirstResponder(recorder))
        let modifiers = NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: [.control, .option, .command], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 55)!
        recorder.flagsChanged(with: modifiers)
        XCTAssertEqual(recorder.liveSymbols, ["⌃", "⌥", "⌘", "…"])
        let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.control, .option, .command], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "k", charactersIgnoringModifiers: "k", isARepeat: false, keyCode: 40)!
        XCTAssertTrue(recorder.performKeyEquivalent(with: key))
        XCTAssertEqual(saved, .standard)
        XCTAssertFalse(recorder.recording)
        recorder.removeFromSuperview()
        window.close()
        saved = nil
        recorder.startRecording()
        recorder.keyDown(with: key)
        XCTAssertEqual(saved, .standard)
        XCTAssertFalse(recorder.recording)
    }

    func testShortcutPreferences() {
        let suite = "Archaive.ShortcutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(Shortcut.load(from: defaults), .standard)
        XCTAssertEqual(Shortcut.standard.label, "⌃⌥⌘K")
        XCTAssertEqual(Shortcut.captured(keyCode: 40, flags: [.control, .option, .command]), .standard)
        XCTAssertEqual(Shortcut.captured(keyCode: 0, flags: [.command, .shift])?.symbols, ["⇧", "⌘", "A"])
        XCTAssertEqual(Shortcut.captured(keyCode: 0, flags: [.command, .capsLock])?.label, "⌘A")
        XCTAssertNil(Shortcut.captured(keyCode: 0, flags: [.shift]))
        XCTAssertNil(Shortcut.captured(keyCode: 53, flags: [.command]))
        XCTAssertNil(Shortcut.captured(keyCode: 0, flags: [.command, .function]))
        let custom = Shortcut(keyCode: 0, modifiers: 256)
        XCTAssertTrue(custom.isValid)
        custom.save(to: defaults)
        XCTAssertEqual(Shortcut.load(from: defaults), custom)
        XCTAssertEqual(custom.label, "⌘A")
        XCTAssertFalse(Shortcut(keyCode: 0, modifiers: 0).isValid)
        XCTAssertFalse(Shortcut(keyCode: 0, modifiers: 512).isValid)
        XCTAssertFalse(Shortcut(keyCode: 999, modifiers: 256).isValid)
        defaults.set(Data("invalid".utf8), forKey: "keepAwakeShortcut")
        XCTAssertEqual(Shortcut.load(from: defaults), .standard)
        Shortcut.standard.save(to: defaults)
        XCTAssertEqual(Shortcut.load(from: defaults), .standard)
    }

    func testPowerStateParsingRejectsMissingOrMalformedState() {
        XCTAssertEqual(System.parseSleepDisabled("System-wide power settings:\n SleepDisabled\t\t0\n"), false)
        XCTAssertEqual(System.parseSleepDisabled(" SleepDisabled 1"), true)
        XCTAssertNil(System.parseSleepDisabled("sleep 1"))
        XCTAssertNil(System.parseSleepDisabled("SleepDisabled unavailable"))
    }

    func testDisconnectGraceAndRetryBackoff() {
        var policy = ReconnectPolicy()
        let start = Date(timeIntervalSince1970: 1000)
        func attempt(_ seconds: Double) -> Bool {
            policy.shouldAttempt(now: start.addingTimeInterval(seconds), enabled: true, wifiOn: true, connected: false, configured: true)
        }
        XCTAssertFalse(attempt(0))
        XCTAssertFalse(attempt(11))
        XCTAssertTrue(attempt(12))
        XCTAssertFalse(attempt(56))
        XCTAssertTrue(attempt(57))
    }

    func testReconnectResetsGraceAndNeverOverridesWifiOff() {
        var policy = ReconnectPolicy()
        let start = Date(timeIntervalSince1970: 1000)
        _ = policy.shouldAttempt(now: start, enabled: true, wifiOn: true, connected: false, configured: true)
        XCTAssertFalse(policy.shouldAttempt(now: start.addingTimeInterval(15), enabled: true, wifiOn: true, connected: true, configured: true))
        XCTAssertNil(policy.disconnectedSince)
        XCTAssertFalse(policy.shouldAttempt(now: start.addingTimeInterval(20), enabled: true, wifiOn: true, connected: false, configured: true))
        XCTAssertFalse(policy.shouldAttempt(now: start.addingTimeInterval(40), enabled: true, wifiOn: false, connected: false, configured: true))
        XCTAssertNil(policy.disconnectedSince)
    }

    func testDisabledOrUnconfiguredNeverJoins() {
        var policy = ReconnectPolicy()
        for time in [0.0, 20.0, 100.0] {
            XCTAssertFalse(policy.shouldAttempt(now: Date(timeIntervalSince1970: time), enabled: false, wifiOn: true, connected: false, configured: true))
            XCTAssertFalse(policy.shouldAttempt(now: Date(timeIntervalSince1970: time), enabled: true, wifiOn: true, connected: false, configured: false))
        }
    }
    func testEmojiNamesAndProcessArguments() {
        for name in ["Vihaan’s iPhone 🔥", "📱", "👨‍👩‍👧‍👦", "Cafe\u{301}", String(repeating: "🔥", count: 8)] {
            XCTAssertNil(System.hotspotNameError(name))
            let result = System.run("/usr/bin/printf", ["%s", name])
            XCTAssertEqual(result.status, 0)
            XCTAssertEqual(result.output, name)
        }
        XCTAssertTrue(System.hotspotNameError(String(repeating: "🔥", count: 9)) != nil)
        XCTAssertTrue(System.hotspotNameError("") != nil)
        XCTAssertTrue(System.hotspotNameError("bad\0name") != nil)
    }

    func testBrightnessRestoreAndFailure() {
        var session = BrightnessSession()
        var levels: [UInt32: Float] = [1: 0.7, 2: 0.4]
        XCTAssertTrue(session.dim(displays: [1, 2, 3], read: { levels[$0] }, write: { levels[$0] = $1; return true }))
        XCTAssertEqual(levels[1], 0)
        XCTAssertEqual(levels[2], 0)
        // Repeated dimming must not replace the original brightness with zero.
        XCTAssertTrue(session.dim(displays: [1], read: { levels[$0] }, write: { levels[$0] = $1; return true }))
        XCTAssertFalse(session.restore { id, value in
            guard id != 2 else { return false }
            levels[id] = value
            return true
        })
        XCTAssertEqual(levels[1], 0.7)
        XCTAssertEqual(session.saved[2], 0.4)
        XCTAssertTrue(session.restore { levels[$0] = $1; return true })
        XCTAssertEqual(levels[2], 0.4)
        XCTAssertTrue(session.saved.isEmpty)
        XCTAssertFalse(session.dim(displays: [3], read: { _ in nil }, write: { _, _ in preconditionFailure("Unsupported display must not be changed") }))
    }

    func testCustomPasswordTransport() {
        let dummy = "test-only 🔥 ' \" $ value"
        XCTAssertNil(System.customPasswordError(dummy))
        XCTAssertTrue(System.customPasswordError("") != nil)
        XCTAssertTrue(System.customPasswordError("bad\nvalue") != nil)
        XCTAssertTrue(System.customPasswordError("bad\0value") != nil)
        let result = System.run("/bin/cat", [], input: Data((dummy + "\n").utf8))
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.output, dummy + "\n")
    }

    func testOnboardingNavigationAndDemoIsolation() {
        let first = OnboardingModel()
        let second = OnboardingModel()
        first.move(-1)
        XCTAssertEqual(first.step, 0)
        first.move(1)
        XCTAssertEqual(first.step, 1)
        XCTAssertTrue(first.forward)
        first.toggleSleep()
        XCTAssertTrue(first.awake)
        XCTAssertTrue(first.practiced)
        XCTAssertFalse(second.awake)
        var located = false
        first.locate = { located = true }
        first.move(20)
        XCTAssertEqual(first.step, 4)
        XCTAssertTrue(located)
        var requestedModes: [Bool] = []
        first.changeMode = { requestedModes.append($0) }
        first.selectSleepMode(awake: false)
        first.selectSleepMode(awake: true)
        XCTAssertEqual(requestedModes, [false, true])
        XCTAssertTrue(first.awake) // Real selections wait for confirmed system state.
        first.actualBusy = true
        first.selectSleepMode(awake: false)
        XCTAssertEqual(requestedModes, [false, true])
        XCTAssertFalse(second.awake)
        first.move(-1)
        XCTAssertEqual(first.step, 3)
        XCTAssertFalse(first.forward)
        var setupCalled = false
        first.setup = { setupCalled = true }
        first.setup?()
        XCTAssertTrue(setupCalled)
        var finished = false
        first.finish = { finished = true }
        first.finish?()
        XCTAssertTrue(finished)
    }

    func testSleepAccessRuleAndInstaller() {
        let rule = SleepAccess.rule(uid: 501)
        XCTAssertTrue(rule.contains("#501 ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1"))
        XCTAssertFalse(rule.contains("NOPASSWD: ALL"))
        XCTAssertFalse(rule.contains("*"))
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("archaive-rule-test-" + UUID().uuidString)
        try! rule.write(to: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: path) }
        let validation = System.run("/usr/sbin/visudo", ["-c", "-f", path.path])
        XCTAssertEqual(validation.status, 0)
        let script = SleepAccess.installScript(uid: 501)
        let syntax = System.run("/bin/sh", ["-n"], input: Data(script.utf8))
        XCTAssertEqual(syntax.status, 0)
        XCTAssertTrue(script.contains("archaive_created=1"))
        XCTAssertTrue(script.contains("/usr/sbin/visudo -cq"))
        let quoted = "literal ' quotes \" and $ characters"
        let shell = System.run("/bin/sh", ["-c", "printf '%s' " + SleepAccess.shellQuote(quoted)])
        XCTAssertEqual(shell.output, quoted)
        // Parsing the generated AppleScript string must not execute the embedded shell script.
        let escaped = System.run("/usr/bin/osascript", ["-e", "return " + SleepAccess.appleScriptQuote(script)])
        XCTAssertEqual(escaped.status, 0)
        XCTAssertEqual(escaped.output.trimmingCharacters(in: .newlines), script.trimmingCharacters(in: .newlines))
    }

}
