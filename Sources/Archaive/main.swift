import AppKit
import CoreImage
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let defaults = UserDefaults.standard
    private let work = DispatchQueue(label: "Archaive.Power")
    private let hotKey = HotKey()
    private let hotspot = Hotspot()
    private let onboarding = OnboardingController()
    private let dashboard = DashboardState()
    private let focus = FocusSession()
    private var dashboardWindow: NSWindow?
    private var focusTimer: Timer?
    private var statusItem: NSStatusItem!
    private let statusIcon = StatusIconAnimator()
    private var timer: Timer?
    private var disabled = false
    private var known = false
    private var busy = false
    private var terminating = false
    private var lastLid: Bool?
    private let brightness = DisplayBrightness()
    private let phoneShare = PhoneShare()
    private var phoneShareWindow: NSWindow?
    private var phoneShareLinks: NSTextView?
    private var phoneShareButton: NSButton?
    private var phoneShareQR: NSImageView?
    private var hotspotWindow: NSWindow?
    private var hotspotInput: NSTextField?
    private var hotspotError: NSTextField?
    private var customPasswordToggle: NSButton?
    private var customPasswordInput: NSSecureTextField?
    private var networkStatus = "Checking Wi-Fi…"
    private var pendingOnboardingMode: Bool?
    private var shortcutOK = false
    private var menu: NSMenu!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent two app instances from competing over the system-wide sleep setting.
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
            exit(0)
        }
        installMainMenu()
        phoneShare.changed = { [weak self] in self?.updatePhoneShare() }
        phoneShare.failed = { [weak self] in self?.showAlert("Phone sharing unavailable", $0) }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(stopPhoneShare), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(stopPhoneShare), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
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
        hotspot.onStatus = { [weak self] status in
            self?.networkStatus = status
            self?.updateDashboard()
        }
        hotspot.start()
        refreshSleep()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.checkLid() }
        let focusTimer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, self.focus.active || self.dashboardWindow?.isVisible == true else { return }
            self.focus.refresh()
        }
        focusTimer.tolerance = 0.25
        RunLoop.main.add(focusTimer, forMode: .common)
        self.focusTimer = focusTimer
        updateIcon()
        rebuildMenu()
        onboarding.saveShortcut = { [weak self] in self?.saveShortcut($0) }
        onboarding.recordingShortcut = { [weak self] in self?.recordingShortcut($0) }
        onboarding.authorize = { [weak self] in self?.setupSleepAccess() }
        onboarding.authorized = { SleepAccess.isInstalled }
        onboarding.currentMode = { [weak self] in guard let self, self.known else { return nil }; return self.disabled }
        onboarding.changeMode = { [weak self] awake in
            guard let self, !self.busy, self.known, self.disabled != awake else { return }
            guard SleepAccess.isInstalled else { self.pendingOnboardingMode = awake; self.setupSleepAccess(); return }
            self.changeSleep(to: awake, restoring: false)
        }
        onboarding.setup = { [weak self] in self?.configureHotspot() }
        onboarding.statusButton = { [weak self] in self?.statusItem.button }
        onboarding.handoff = { [weak self] in self?.showDashboard() }
        if defaults.object(forKey: "originalSleepDisabled") != nil {
            showAlert("Unfinished awake session", "Archaive previously changed your sleep setting. Open Keep Awake and choose Restore to recover it. Until then, your Mac may stay awake with the lid closed.")
        }
        showDashboard()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.dashboardWindow?.isVisible == true,
                  !self.defaults.bool(forKey: "hasCompletedOnboarding") else { return }
            self.onboarding.present()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showDashboard()
        return false
    }

    @objc private func showDashboard() {
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
        if let tour = onboarding.window { tour.makeKeyAndOrderFront(nil); return }
        if dashboardWindow == nil {
            let actions = DashboardActions(
                addApps: { [weak self] in
                    guard let self, let window = self.dashboardWindow else { return }
                    self.focus.addApps(in: window)
                },
                toggleSleep: { [weak self] in self?.toggleSleep() },
                toggleDimming: { [weak self] in self?.toggleDimming() },
                setupSleepAccess: { [weak self] in self?.setupSleepAccess() },
                removeSleepAccess: { [weak self] in self?.removeSleepAccess() },
                restoreSleep: { [weak self] in self?.restoreSleep() },
                saveShortcut: { [weak self] in self?.saveShortcut($0) },
                recordingShortcut: { [weak self] in self?.recordingShortcut($0) },
                configureHotspot: { [weak self] in self?.configureHotspot() },
                toggleHotspot: { [weak self] in self?.toggleHotspot() },
                configureShare: { [weak self] in self?.showPhoneShare() },
                stopShare: { [weak self] in self?.stopPhoneShare() },
                replayTour: { [weak self] in self?.replayOnboarding() }
            )
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 590),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "Archaive"
            window.titleVisibility = .hidden
            window.delegate = self
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: Dashboard(state: dashboard, focus: focus, actions: actions))
            window.contentMinSize = NSSize(width: 680, height: 480)
            window.center()
            dashboardWindow = window
        }
        updateDashboard()
        refreshSleep()
        focus.refresh()
        NSApp.activate(ignoringOtherApps: true)
        if dashboardWindow?.isMiniaturized == true { dashboardWindow?.deminiaturize(nil) }
        dashboardWindow?.makeKeyAndOrderFront(nil)
    }

    private func updateDashboard() {
        let value = DashboardState.Status(
            awake: known ? disabled : nil, busy: busy, dim: defaults.bool(forKey: "dimOnClose"),
            authorized: SleepAccess.isInstalled, canRestore: defaults.object(forKey: "originalSleepDisabled") != nil,
            shortcut: hotKey.shortcut, shortcutAvailable: shortcutOK,
            hotspotName: defaults.string(forKey: "hotspotName"), hotspotEnabled: defaults.bool(forKey: "hotspotEnabled"),
            network: networkStatus, sharing: phoneShare.active, startingShare: phoneShare.starting)
        if dashboard.status != value { dashboard.status = value }
    }

    func menuWillOpen(_ menu: NSMenu) {
        if menu === self.menu { rebuildMenu(); refreshSleep() }
    }

    private func rebuildMenu() {
        onboarding.model.actualBusy = busy
        onboarding.model.actualAwake = known ? disabled : nil
        populateMenu(menu)
        updateDashboard()
    }

    private func populateMenu(_ menu: NSMenu) {
        @discardableResult
        func item(_ title: String, _ action: Selector) -> NSMenuItem {
            let row = NSMenuItem(title: title, action: action, keyEquivalent: "")
            row.target = self
            menu.addItem(row)
            return row
        }
        menu.autoenablesItems = false
        menu.removeAllItems()
        item("Open Archaive", #selector(showDashboard))
        if focus.active && focus.enabled { item("Turn Off Focus", #selector(disableFocusFromMenu)) }
        menu.addItem(.separator())
        item(disabled ? "Allow Sleep" : "Keep Awake", #selector(toggleSleep)).isEnabled = !busy && known
        if phoneShare.active || phoneShare.starting { item("Stop Phone Sharing", #selector(stopPhoneShare)) }
        menu.addItem(.separator())
        item("Quit Archaive", #selector(quit)).isEnabled = !busy
    }

    @objc private func showPhoneShare() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = phoneShareWindow { window.makeKeyAndOrderFront(nil); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 330), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Share your Mac to your phone"
        window.delegate = self
        window.isReleasedWhenClosed = false
        let help = NSTextField(wrappingLabelWithString: "Connect your iPhone and Mac to the same Wi-Fi or phone hotspot. Start sharing, then scan this QR code inside the Archaive iPhone app. You can also open a sharing link in Safari or Chrome.")
        help.frame = NSRect(x: 20, y: 229, width: 460, height: 80)
        window.contentView?.addSubview(help)
        let scroll = NSScrollView(frame: NSRect(x: 20, y: 115, width: 310, height: 105))
        scroll.hasVerticalScroller = true
        let links = NSTextView(frame: scroll.bounds)
        links.isEditable = false
        links.isSelectable = true
        links.font = .systemFont(ofSize: 14)
        links.textContainer?.widthTracksTextView = true
        links.autoresizingMask = [.width]
        scroll.documentView = links
        window.contentView?.addSubview(scroll)
        let qr = NSImageView(frame: NSRect(x: 365, y: 115, width: 115, height: 115))
        qr.imageScaling = .scaleProportionallyUpOrDown
        qr.setAccessibilityLabel("Scan with your phone camera to open the screen viewer")
        window.contentView?.addSubview(qr)
        phoneShareQR = qr
        let copy = NSButton(title: "Copy Link", target: self, action: #selector(copyPhoneShareLink))
        copy.frame = NSRect(x: 20, y: 12, width: 120, height: 32)
        copy.bezelStyle = .rounded
        window.contentView?.addSubview(copy)
        let note = NSTextField(wrappingLabelWithString: "View only. Physical dimming stays on. Anyone with the link can view your screen over this unencrypted local connection; use a trusted network. Locking your Mac stops sharing.")
        note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        note.textColor = .secondaryLabelColor
        note.frame = NSRect(x: 20, y: 55, width: 460, height: 53)
        window.contentView?.addSubview(note)
        let button = NSButton(title: "Start Sharing", target: self, action: #selector(togglePhoneShare))
        button.frame = NSRect(x: 320, y: 12, width: 160, height: 32)
        button.bezelStyle = .rounded
        window.contentView?.addSubview(button)
        phoneShareWindow = window
        phoneShareLinks = links
        phoneShareButton = button
        updatePhoneShare()
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func copyPhoneShareLink() {
        guard let link = phoneShare.links.first else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)
    }

    private func updatePhoneShare() {
        phoneShareQR?.image = nil
        if let link = phoneShare.links.first,
           let filter = CIFilter(name: "CIQRCodeGenerator") {
            filter.setValue(Data(link.utf8), forKey: "inputMessage")
            if let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 5, y: 5)),
               let image = CIContext().createCGImage(output.composited(over: CIImage(color: .white)), from: output.extent.insetBy(dx: -20, dy: -20)) {
                phoneShareQR?.image = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            }
        }
        phoneShareButton?.title = phoneShare.active || phoneShare.starting ? "Stop Sharing" : "Start Sharing"
        phoneShareLinks?.string = phoneShare.starting ? "Waiting for screen-capture permission…" : phoneShare.active ? (phoneShare.links.isEmpty ? "No local IPv4 address. Connect to Wi-Fi, then stop and restart sharing." : phoneShare.links.joined(separator: "\n\n")) : "Sharing is off. Start sharing to create a new private session link."
        rebuildMenu()
    }

    @objc private func togglePhoneShare() {
        if phoneShare.active || phoneShare.starting { phoneShare.stop() }
        else { phoneShare.start() }
    }

    @objc private func stopPhoneShare() { phoneShare.stop() }

    @objc private func disableFocusFromMenu() { focus.setEnabled(false) }

    private func recordingShortcut(_ recording: Bool) {
        onboarding.model.recordingShortcut = recording
        if recording { hotKey.suspend() }
        else { shortcutOK = hotKey.register(); updateDashboard() }
    }

    private func saveShortcut(_ candidate: Shortcut) -> String? {
        guard candidate.isValid else { return "Include Command, Option, or Control with a letter or number." }
        guard hotKey.register(candidate) else { return "Shortcut in use. Try another combination." }
        candidate.save(to: defaults)
        shortcutOK = true
        onboarding.model.shortcut = candidate
        updateIcon()
        return nil
    }

    @objc private func replayOnboarding() { onboarding.present() }

    private func updateIcon() {
        updateDashboard()
        onboarding.model.actualAwake = known ? disabled : nil
        guard let button = statusItem.button else { return }
        button.toolTip = "Archaive · \(disabled ? "Awake" : "Normal sleep") · \(hotKey.shortcut.label)"
        statusIcon.update(button: button, awake: disabled)
    }

    private func updateConfirmedSleep(_ value: Bool?) {
        known = value != nil
        if let value { disabled = value }
        if value == true && focus.closedLidOnly { focus.setLidClosed(System.lidClosed()) }
        focus.setKeepAwake(value == true)
    }

    private func refreshSleep() {
        guard !busy else { return }
        work.async {
            let value = System.sleepDisabled()
            DispatchQueue.main.async {
                guard !self.busy else { return }
                self.updateConfirmedSleep(value)
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
        updateDashboard()
        work.async {
            let result = SleepAccess.install()
            DispatchQueue.main.async {
                self.busy = false
                let message = result.status == 0 ? "Ready. Keep-awake toggles no longer ask for your password." : "Setup cancelled or failed. You can retry. " + result.output
                self.onboarding.authorizationFinished(success: result.status == 0, message: message)
                if let requested = self.pendingOnboardingMode {
                    self.pendingOnboardingMode = nil
                    if result.status == 0 { self.changeSleep(to: requested, restoring: false) }
                }
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
        updateDashboard()
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
                self.updateConfirmedSleep(after)
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
                    self.showAlert("Sleep setting was not changed", result.output.isEmpty ? "macOS did not confirm the requested setting. Try again from Keep Awake." : result.output)
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
        let lid = System.lidClosed()
        focus.setLidClosed(lid)
        guard let closed = lid else { lastLid = nil; return }
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
        updateDashboard()
    }

    @objc private func toggleHotspot() {
        if defaults.string(forKey: "hotspotName")?.isEmpty ?? true { configureHotspot(); return }
        defaults.set(!defaults.bool(forKey: "hotspotEnabled"), forKey: "hotspotEnabled")
        updateDashboard()
    }

    private func installMainMenu() {
        let main = NSMenu()
        let appRoot = NSMenuItem(title: "Archaive", action: nil, keyEquivalent: "")
        appRoot.submenu = NSMenu(title: "Archaive")
        let aboutItem = appRoot.submenu!.addItem(withTitle: "About Archaive", action: #selector(about), keyEquivalent: "")
        aboutItem.target = self
        appRoot.submenu!.addItem(.separator())
        let hideItem = appRoot.submenu!.addItem(withTitle: "Hide Archaive", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hideItem.target = NSApp
        appRoot.submenu!.addItem(.separator())
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
        let windowRoot = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        let windowMenu = NSMenu(title: "Window")
        let openItem = windowMenu.addItem(withTitle: "Open Archaive", action: #selector(showDashboard), keyEquivalent: "0")
        openItem.target = self
        windowMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowRoot.submenu = windowMenu
        main.addItem(windowRoot)
        NSApp.windowsMenu = windowMenu
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
        updateDashboard()
    }

    func windowWillClose(_ notification: Notification) {
        if let closing = notification.object as? NSWindow, closing === hotspotWindow {
            customPasswordInput?.stringValue = ""
            hotspotWindow = nil
            onboarding.setupFinished(saved: false)
        }

        // Wait until AppKit finishes closing the window before checking visibility.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let windows = [self.dashboardWindow, self.hotspotWindow, self.phoneShareWindow, self.onboarding.window]
            let hasOpenWindow = windows.compactMap { $0 }.contains { $0.isVisible || $0.isMiniaturized }
            if !hasOpenWindow { NSApp.setActivationPolicy(.accessory) }
        }
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

    func applicationWillTerminate(_ notification: Notification) {
        focus.setKeepAwake(false)
        phoneShare.stop()
    }

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

if CommandLine.arguments.dropFirst().first == FocusPauseWorker.argument {
    FocusPauseWorker.run()
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
