import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let defaults = UserDefaults.standard
    private let work = DispatchQueue(label: "Archaive.Power")
    private let hotKey = HotKey()
    private let shortcutPopover = ShortcutPopover()
    private let hotspot = Hotspot()
    private let onboarding = OnboardingController()
    private var statusItem: NSStatusItem!
    private let statusIcon = StatusIconAnimator()
    private var timer: Timer?
    private var disabled = false
    private var known = false
    private var busy = false
    private var terminating = false
    private var lastLid: Bool?
    private let brightness = DisplayBrightness()
    private var hotspotWindow: NSWindow?
    private var hotspotInput: NSTextField?
    private var hotspotError: NSTextField?
    private var customPasswordToggle: NSButton?
    private var customPasswordInput: NSSecureTextField?
    private var networkStatus = "Checking Wi-Fi…"
    private var shortcutOK = false
    private var menu: NSMenu!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent two app instances from competing over the system-wide sleep setting.
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
            exit(0)
        }
        installEditMenu()
        brightness.rememberDisplays()
        defaults.register(defaults: ["dimOnClose": true])
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        hotKey.action = { [weak self] in
            guard let self, !self.onboarding.handleShortcut() else { return }
            self.toggleSleep()
        }
        shortcutOK = hotKey.register()
        hotspot.onStatus = { [weak self] in self?.networkStatus = $0 }
        hotspot.start()
        refreshSleep()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.checkLid() }
        updateIcon()
        rebuildMenu()
        onboarding.saveShortcut = { [weak self] in self?.saveShortcut($0) }
        onboarding.recordingShortcut = { [weak self] in self?.recordingShortcut($0) }
        onboarding.authorize = { [weak self] in self?.setupSleepAccess() }
        onboarding.authorized = { SleepAccess.isInstalled }
        onboarding.setup = { [weak self] in self?.configureHotspot() }
        onboarding.statusButton = { [weak self] in self?.statusItem.button }
        onboarding.handoff = { [weak self] in self?.statusItem.button?.performClick(nil) }
        if defaults.object(forKey: "originalSleepDisabled") != nil {
            showAlert("Unfinished awake session", "Archaive previously changed your sleep setting. Choose Restore Previous Sleep Setting from the menu to recover it. Until then, your Mac may stay awake with the lid closed.")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, !self.defaults.bool(forKey: "hasCompletedOnboarding") else { return }
            self.onboarding.present()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        if menu === self.menu { rebuildMenu(); refreshSleep() }
    }

    private func rebuildMenu() { populateMenu(menu) }

    private func populateMenu(_ menu: NSMenu) {
        @discardableResult
        func item(_ title: String, _ action: Selector? = nil, checked: Bool? = nil) -> NSMenuItem {
            let row = NSMenuItem(title: title, action: action, keyEquivalent: "")
            row.target = self
            row.isEnabled = action != nil
            if let checked { row.state = checked ? .on : .off }
            menu.addItem(row)
            return row
        }
        menu.autoenablesItems = false
        menu.removeAllItems()
        let awake = disabled
        if busy {
            item("Updating sleep setting…")
        } else if !known {
            item("Sleep setting unavailable")
        } else {
            item(awake ? "Mac stays awake" : "Mac sleeps normally")
        }
        let shortcutRow = NSMenuItem()
        shortcutRow.isEnabled = !busy && known
        shortcutRow.view = ShortcutMenuRow(shortcut: hotKey.shortcut, awake: awake,
            enabled: !busy && known,
            toggle: { [weak self, weak menu] in
                menu?.cancelTracking()
                self?.toggleSleep()
            }, edit: { [weak self, weak menu] in
                menu?.cancelTracking()
                DispatchQueue.main.async { self?.editShortcut() }
            })
        menu.addItem(shortcutRow)
        if !shortcutOK { item("Shortcut unavailable — click to edit") }
        item("Fully Dim When Lid Closes", #selector(toggleDimming), checked: defaults.bool(forKey: "dimOnClose"))
            .toolTip = lastLid.map { $0 ? "Lid closed" : "Lid open" } ?? "Lid sensor unavailable"
        menu.addItem(.separator())
        item("Auto-Connect to Hotspot", #selector(toggleHotspot), checked: defaults.bool(forKey: "hotspotEnabled"))
            .toolTip = [defaults.string(forKey: "hotspotName"), networkStatus].compactMap { $0 }.joined(separator: " · ")
        item("Hotspot Settings…", #selector(configureHotspot))
        menu.addItem(.separator())
        if defaults.object(forKey: "originalSleepDisabled") != nil {
            item("Restore Previous Sleep Setting", #selector(restoreSleep)).isEnabled = !busy
        }
        item(SleepAccess.isInstalled ? "Remove Password-Free Access…" : "Set Up Password-Free Toggles…", SleepAccess.isInstalled ? #selector(removeSleepAccess) : #selector(setupSleepAccess))
            .isEnabled = !busy
        item("Replay Welcome Tour…", #selector(replayOnboarding))
        item("About Archaive…", #selector(about))
        item("Quit Archaive", #selector(quit)).isEnabled = !busy
    }

    private func editShortcut() {
        guard let button = statusItem.button else { return }
        shortcutPopover.show(from: button, shortcut: hotKey.shortcut,
            save: { [weak self] in self?.saveShortcut($0) },
            recordingChanged: { [weak self] in self?.recordingShortcut($0) })
    }

    private func recordingShortcut(_ recording: Bool) {
        onboarding.model.recordingShortcut = recording
        if recording { hotKey.suspend() }
        else { shortcutOK = hotKey.register() }
    }

    private func saveShortcut(_ candidate: Shortcut) -> String? {
        guard candidate.isValid else { return "Include Command, Option, or Control with a letter or number." }
        guard hotKey.register(candidate) else { return "Shortcut in use. Try another combination." }
        candidate.save(to: defaults)
        shortcutOK = true
        onboarding.model.shortcut = candidate
        updateIcon()
        // Rebuild the status menu on its next opening, after tracking ends.
        return nil
    }

    @objc private func replayOnboarding() { onboarding.present() }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        button.toolTip = "Archaive · \(disabled ? "Awake" : "Normal sleep") · \(hotKey.shortcut.label)"
        statusIcon.update(button: button, awake: disabled)
    }

    private func refreshSleep() {
        guard !busy else { return }
        work.async {
            let value = System.sleepDisabled()
            DispatchQueue.main.async {
                guard !self.busy else { return }
                self.known = value != nil
                if let value { self.disabled = value }
                self.updateIcon()
            }
        }
    }

    @objc private func toggleSleep() {
        guard !busy, known else { return }
        guard SleepAccess.isInstalled else { setupSleepAccess(); return }
        changeSleep(to: !disabled, restoring: false)
    }

    @objc private func setupSleepAccess() {
        guard !busy else { return }
        guard !SleepAccess.isInstalled else { onboarding.authorizationFinished(success: true, message: "Already set up. Toggles need no password."); return }
        busy = true
        onboarding.authorizationStarted()
        work.async {
            let result = SleepAccess.install()
            DispatchQueue.main.async {
                self.busy = false
                let message = result.status == 0 ? "Ready. Keep-awake toggles no longer ask for your password." : "Setup cancelled or failed. You can retry. " + result.output
                self.onboarding.authorizationFinished(success: result.status == 0, message: message)
                if !self.onboarding.isPresented { self.showAlert(result.status == 0 ? "One-time setup complete" : "Setup not completed", message) }
                self.rebuildMenu()
            }
        }
    }

    @objc private func removeSleepAccess() {
        guard !busy else { return }
        guard !disabled, defaults.object(forKey: "originalSleepDisabled") == nil else {
            showAlert("Restore sleep first", "Turn keep awake off and restore any previous sleep setting before removing access.")
            return
        }
        busy = true
        work.async {
            let result = SleepAccess.remove()
            DispatchQueue.main.async {
                self.busy = false
                self.showAlert(result.status == 0 ? "Password-free access removed" : "Could not remove access", result.status == 0 ? "Future toggles require one-time setup again." : result.output)
                self.rebuildMenu()
            }
        }
    }

    @objc private func restoreSleep() {
        guard let original = defaults.object(forKey: "originalSleepDisabled") as? Bool, !busy else { return }
        guard SleepAccess.isInstalled else { setupSleepAccess(); return }
        changeSleep(to: original, restoring: true)
    }

    private func changeSleep(to value: Bool, restoring: Bool, completion: (() -> Void)? = nil) {
        busy = true
        rebuildMenu()
        work.async {
            guard let before = System.sleepDisabled() else {
                DispatchQueue.main.async { self.finishError("Could not read the current sleep setting.") }
                return
            }
            // Persist recovery before changing the machine, including if the app is killed mid-command.
            if self.defaults.object(forKey: "originalSleepDisabled") == nil {
                self.defaults.set(before, forKey: "originalSleepDisabled")
                self.defaults.synchronize()
            }
            let result = System.setSleepDisabled(value)
            let after = System.sleepDisabled()
            DispatchQueue.main.async {
                self.busy = false
                self.known = after != nil
                if let after { self.disabled = after }
                if result.status == 0 && after == value {
                    if restoring || self.defaults.bool(forKey: "originalSleepDisabled") == value {
                        self.defaults.removeObject(forKey: "originalSleepDisabled")
                    }
                    self.lastLid = nil
                    self.checkLid()
                    completion?()
                } else {
                    if after == self.defaults.object(forKey: "originalSleepDisabled") as? Bool {
                        self.defaults.removeObject(forKey: "originalSleepDisabled")
                    }
                    self.cancelTermination()
                    self.showAlert("Sleep setting was not changed", result.output.isEmpty ? "macOS did not confirm the requested setting. Try again from the menu." : result.output)
                }
                self.updateIcon()
                self.rebuildMenu()
            }
        }
    }

    private func finishError(_ text: String) {
        busy = false
        cancelTermination()
        showAlert("Unable to change sleep", text)
        rebuildMenu()
    }

    private func checkLid() {
        guard let closed = System.lidClosed() else { lastLid = nil; return }
        let changed = closed != lastLid
        lastLid = closed
        if closed && changed && disabled && defaults.bool(forKey: "dimOnClose") {
            if !brightness.dim() {
                showAlert("Brightness control unavailable", "Archaive could not dim this display. It will not put the display to sleep. Some external monitors do not support brightness control.")
            }
        } else if !closed || !disabled || !defaults.bool(forKey: "dimOnClose") {
            brightness.restore()
            if !closed { brightness.rememberDisplays() }
        }
    }

    @objc private func toggleDimming() {
        defaults.set(!defaults.bool(forKey: "dimOnClose"), forKey: "dimOnClose")
        lastLid = nil
        checkLid()
    }

    @objc private func toggleHotspot() {
        if defaults.string(forKey: "hotspotName")?.isEmpty ?? true { configureHotspot(); return }
        defaults.set(!defaults.bool(forKey: "hotspotEnabled"), forKey: "hotspotEnabled")
    }

    private func installEditMenu() {
        let main = NSMenu()
        let appRoot = NSMenuItem(title: "Archaive", action: nil, keyEquivalent: "")
        appRoot.submenu = NSMenu(title: "Archaive")
        let quitItem = appRoot.submenu!.addItem(withTitle: "Quit Archaive", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        main.addItem(appRoot)
        let root = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "Edit")
        for (title, action, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        edit.addItem(.separator())
        let emoji = edit.addItem(withTitle: "Emoji & Symbols", action: #selector(NSApplication.orderFrontCharacterPalette(_:)), keyEquivalent: "")
        emoji.target = NSApp
        root.submenu = edit
        main.addItem(root)
        NSApp.mainMenu = main
    }

    @objc private func configureHotspot() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = hotspotWindow { window.makeKeyAndOrderFront(nil); return }
        // A normal window allows Character Viewer and the standard field editor to operate.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 355), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Your hotspot"
        window.delegate = self
        window.isReleasedWhenClosed = false
        let content = window.contentView!
        let help = NSTextField(wrappingLabelWithString: "Enter the exact Wi-Fi name, including emoji. By default, Archaive uses the password saved by macOS.")
        help.frame = NSRect(x: 20, y: 282, width: 380, height: 53)
        content.addSubview(help)
        let input = NSTextField(frame: NSRect(x: 20, y: 242, width: 330, height: 26))
        input.placeholderString = "Hotspot Wi-Fi name"
        input.stringValue = defaults.string(forKey: "hotspotName") ?? ""
        input.setAccessibilityLabel("Hotspot Wi-Fi name")
        content.addSubview(input)
        let emoji = NSButton(title: "☺", target: NSApp, action: #selector(NSApplication.orderFrontCharacterPalette(_:)))
        emoji.frame = NSRect(x: 355, y: 240, width: 45, height: 30)
        emoji.setAccessibilityLabel("Emoji and Symbols")
        content.addSubview(emoji)
        let toggle = NSButton(checkboxWithTitle: "Use Custom Password", target: self, action: #selector(toggleCustomPassword))
        toggle.frame = NSRect(x: 20, y: 204, width: 380, height: 24)
        toggle.state = defaults.bool(forKey: "hotspotUseCustomPassword") ? .on : .off
        content.addSubview(toggle)
        let password = NSSecureTextField(frame: NSRect(x: 20, y: 168, width: 380, height: 26))
        password.placeholderString = "Enter password; leave blank to keep stored custom password"
        password.setAccessibilityLabel("Custom hotspot password")
        password.isEnabled = toggle.state == .on
        content.addSubview(password)
        let note = NSTextField(wrappingLabelWithString: "Stored securely in Keychain. Joining may also update macOS’s saved Wi-Fi password.")
        note.frame = NSRect(x: 20, y: 114, width: 380, height: 44)
        note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        note.textColor = .secondaryLabelColor
        content.addSubview(note)
        customPasswordToggle = toggle
        customPasswordInput = password
        let error = NSTextField(wrappingLabelWithString: "")
        error.frame = NSRect(x: 20, y: 59, width: 380, height: 50)
        error.textColor = .systemRed
        content.addSubview(error)
        let save = NSButton(title: "Save & Enable", target: self, action: #selector(saveHotspot))
        save.frame = NSRect(x: 265, y: 15, width: 140, height: 32)
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"
        content.addSubview(save)
        hotspotInput = input
        hotspotError = error
        hotspotWindow = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(input)
    }

    @objc private func toggleCustomPassword() {
        customPasswordInput?.isEnabled = customPasswordToggle?.state == .on
        hotspotError?.stringValue = ""
    }

    @objc private func saveHotspot() {
        guard let input = hotspotInput else { return }
        let name = input.stringValue
        if let error = System.hotspotNameError(name) { hotspotError?.stringValue = error; return }
        let useCustom = customPasswordToggle?.state == .on
        if useCustom {
            do {
                let entered = customPasswordInput?.stringValue ?? ""
                let password: String
                if entered.isEmpty { password = try HotspotPassword.read(for: name) ?? "" }
                else { password = entered }
                if let error = System.customPasswordError(password) { hotspotError?.stringValue = error; return }
                if !entered.isEmpty { try HotspotPassword.save(password, for: name) }
            } catch { hotspotError?.stringValue = error.localizedDescription; return }
        }
        defaults.set(useCustom, forKey: "hotspotUseCustomPassword")
        defaults.set(name, forKey: "hotspotName")
        defaults.set(true, forKey: "hotspotEnabled")
        hotspotWindow?.close()
        hotspotWindow = nil
        hotspotInput = nil
        hotspotError = nil
        customPasswordInput?.stringValue = ""
        customPasswordInput = nil
        customPasswordToggle = nil
        onboarding.setupFinished(saved: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing === hotspotWindow else { return }
        customPasswordInput?.stringValue = ""
        hotspotWindow = nil
        onboarding.setupFinished(saved: false)
    }

    @objc private func about() {
        showAlert("Archaive", "\(hotKey.shortcut.label) toggles keep awake, including with the lid closed. One-time setup asks for administrator access. After setup, toggles need no password.\n\nClosing the lid sets supported displays to zero brightness while keep awake is enabled. Opening the lid restores brightness. This does not request display sleep or lock the screen. This uses the lid switch, not hinge angle, and does not control keyboard lighting.\n\nQuit restores your previous sleep setting. Force Quit or a crash can leave sleep disabled; reopen Archaive to restore it. An awake Mac still uses battery and generates heat, so do not store it in a bag while enabled.")
    }

    private func showAlert(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    private func cancelTermination() {
        if terminating { terminating = false; NSApp.reply(toApplicationShouldTerminate: false) }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !busy else { return .terminateCancel }
        guard brightness.restore() else {
            showAlert("Brightness could not be restored", "Reconnect your display and try quitting again, or restore brightness using the keyboard controls.")
            return .terminateCancel
        }
        guard let original = defaults.object(forKey: "originalSleepDisabled") as? Bool else { return .terminateNow }
        guard SleepAccess.isInstalled else { setupSleepAccess(); return .terminateCancel }
        terminating = true
        changeSleep(to: original, restoring: true) { NSApp.reply(toApplicationShouldTerminate: true) }
        // If restoration is cancelled or fails, keep the app running and permit a later quit attempt.
        return .terminateLater
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
