import Foundation

func XCTAssertEqual<T: Equatable>(_ actual: T, _ expected: T) { precondition(actual == expected) }
func XCTAssertNil<T>(_ value: T?) { precondition(value == nil) }
func XCTAssertTrue(_ value: Bool) { precondition(value) }
func XCTAssertFalse(_ value: Bool) { precondition(!value) }

@main
struct PolicyTests {
    static func main() {
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
        print("10 regression tests passed")
    }
    func testShortcutPreferences() {
        let suite = "Archaive.ShortcutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(Shortcut.load(from: defaults), .standard)
        XCTAssertEqual(Shortcut.standard.label, "⌃⌥⌘K")
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
        first.toggleDimming()
        first.toggleHotspot()
        XCTAssertTrue(first.awake)
        XCTAssertTrue(first.practiced)
        XCTAssertFalse(first.dim)
        XCTAssertTrue(first.hotspot)
        XCTAssertFalse(second.awake)
        XCTAssertTrue(second.dim)
        XCTAssertFalse(second.hotspot)
        var located = false
        first.locate = { located = true }
        first.move(20)
        XCTAssertEqual(first.step, 4)
        XCTAssertTrue(located)
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
