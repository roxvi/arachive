import AppKit
import SwiftUI
import QuartzCore

final class OnboardingModel: NSObject, ObservableObject {
    @Published var shortcut = Shortcut.load()
    var recordingShortcut = false
    @Published var step = 0
    @Published var forward = true
    @Published var actualAwake: Bool?
    @Published var actualBusy = false
    var changeMode: ((Bool) -> Void)?
    @Published var awake = false
    @Published var lidClosed = false
    @Published var practiced = false
    @Published var setupStatus = "Optional. You can set this up later from the menu."
    @Published var authorizationStatus = "Approve once. Future keep-awake toggles need no password."
    @Published var authorizationBusy = false
    @Published var authorizationReady = false
    var saveShortcut: ((Shortcut) -> String?)?
    var recordingChanged: ((Bool) -> Void)?
    var authorize: (() -> Void)?
    @Published var target: CGPoint?
    var finish: (() -> Void)?
    var setup: (() -> Void)?
    var locate: (() -> Void)?

    func move(_ delta: Int) {
        forward = delta > 0
        step = min(4, max(0, step + delta))
        if step == 4 { locate?() }
    }
    @objc func toggleSleep() { awake.toggle(); practiced = true }
    func selectSleepMode(awake: Bool) { guard !actualBusy else { return }; changeMode?(awake) }
}

private final class TakeoverWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class OnboardingController {
    private(set) var window: NSWindow?
    private(set) var model = OnboardingModel()
    private weak var previousWindow: NSWindow?
    var isPresented: Bool { window != nil }
    var setup: (() -> Void)?
    var statusButton: (() -> NSStatusBarButton?)?
    var handoff: (() -> Void)?
    var saveShortcut: ((Shortcut) -> String?)?
    var recordingShortcut: ((Bool) -> Void)?
    var authorize: (() -> Void)?
    var authorized: (() -> Bool)?
    var currentMode: (() -> Bool?)?
    var changeMode: ((Bool) -> Void)?
    private var escaping: Any?

    func present() {
        guard window == nil else { window?.makeKeyAndOrderFront(nil); return }
        guard let screen = statusButton?()?.window?.screen ?? NSApp.keyWindow?.screen ?? NSScreen.main else { return }
        previousWindow = NSApp.keyWindow
        model = OnboardingModel()
        model.actualAwake = currentMode?()
        model.changeMode = { [weak self] in self?.changeMode?($0) }
        model.authorizationReady = authorized?() ?? false
        if model.authorizationReady { model.authorizationStatus = "Already approved. Toggles need no password." }
        model.authorize = { [weak self] in self?.authorize?() }
        model.saveShortcut = { [weak self] in self?.saveShortcut?($0) }
        model.recordingChanged = { [weak self] in self?.recordingShortcut?($0) }
        let panel = TakeoverWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        panel.appearance = NSAppearance(named: .aqua)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        model.finish = { [weak self] in self?.dismiss() }
        model.setup = { [weak self] in
            guard let self else { return }
            self.model.setupStatus = "Hotspot Settings is open. Save to enable, or close it to skip."
            self.window?.level = .normal
            self.setup?()
        }
        model.locate = { [weak self] in self?.locateIcon() }
        panel.contentView = NSHostingView(rootView: OnboardingView(model: model, captureThemeFrame: { [weak panel] in
            panel?.captureThemeFrame()
        }))
        window = panel
        escaping = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true else { return event }
            if event.keyCode == 53 && !self.model.recordingShortcut { self.dismiss(); return nil }
            return event
        }
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.12 : 0.32
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 1
        }
    }

    func handleShortcut() -> Bool {
        guard isPresented else { return false }
        if model.step == 1 && !model.recordingShortcut { model.toggleSleep() }
        return true // Never change the machine from a tutorial shortcut.
    }

    func authorizationStarted() {
        model.authorizationBusy = true
        model.authorizationStatus = "Waiting for administrator approval…"
        window?.level = .normal
    }

    func authorizationFinished(success: Bool, message: String) {
        model.authorizationBusy = false
        model.authorizationReady = success
        model.authorizationStatus = message
        window?.level = .floating
        window?.makeKeyAndOrderFront(nil)
    }

    func setupFinished(saved: Bool) {
        guard isPresented else { return }
        model.setupStatus = saved ? "Hotspot saved. Automatic fallback is enabled." : "Nothing changed. Try again, or continue without a hotspot."
        window?.level = .floating
        window?.makeKeyAndOrderFront(nil)
    }

    private func locateIcon() {
        guard let panel = window, let button = statusButton?(), let barWindow = button.window else { model.target = nil; return }
        let rect = barWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let point = CGPoint(x: rect.midX - panel.frame.minX, y: panel.frame.maxY - rect.midY)
        if point.x >= 0 && point.x <= panel.frame.width && point.y >= 0 && point.y <= 80 {
            model.target = point
        } else { model.target = nil }
    }

    func dismiss() {
        guard let panel = window, escaping != nil else { return }
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        if let escaping { NSEvent.removeMonitor(escaping); self.escaping = nil }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.12 : 0.24
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, weak panel] in
            guard let self, let panel, self.window === panel else { return }
            panel.orderOut(nil)
            self.window = nil
            if self.model.step == 4 { self.handoff?() }
            else { self.previousWindow?.makeKeyAndOrderFront(nil) }
        }
    }
}

private struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    let captureThemeFrame: () -> NSImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppTheme.storageKey) private var themeID = ""
    @State private var logoRevealed = false
    @State private var inkTransition: ThemeInkTransition?

    private var theme: AppTheme { AppTheme(rawValue: themeID) ?? .defaultTheme }

    var body: some View {
        GeometryReader { geometry in
            let margin: CGFloat = geometry.size.width < 680 ? 20 : 38
            ZStack {
                ThemeCanvas(theme: theme, glass: true)
                if model.step == 4, let target = model.target {
                    MenuBarPointer(target: target)
                        .stroke(theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                VStack(spacing: 14) {
                    topRail
                    GeometryReader { viewport in
                        HStack(spacing: 0) {
                            ForEach(0..<5) { step in
                                Group {
                                    if step == 0 { welcome }
                                    else { TourPage(model: model, step: step) }
                                }
                                .frame(width: viewport.size.width, height: viewport.size.height)
                                .disabled(step != model.step)
                                .allowsHitTesting(step == model.step)
                                .accessibilityHidden(step != model.step)
                            }
                        }
                        .offset(x: -CGFloat(model.step) * viewport.size.width)
                        .animation(reduceMotion ? nil : .spring(response: 0.57, dampingFraction: 0.9), value: model.step)
                        .frame(width: viewport.size.width, alignment: .leading)
                    }
                    .clipped()
                    bottomRail
                }
                .padding(.horizontal, margin)
                .padding(.top, 42)
                .padding(.bottom, 25)
            }
            .themeInkTransition($inkTransition)
            .foregroundStyle(theme.ink)
            .environment(\.appTheme, theme)
            .environment(\.colorScheme, .light)
            .tint(theme.accent)
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.66, dampingFraction: 0.68).delay(0.12)) {
                logoRevealed = true
            }
        }
    }

    private var topRail: some View {
        HStack {
            Wordmark(width: 132)
                .foregroundStyle(theme.accent)
                .opacity(model.step == 0 ? 0 : 1)
                .accessibilityHidden(model.step == 0)
            Spacer()
            Button("Skip Setup") { model.finish?() }.buttonStyle(InkButton(prominent: false))
        }
    }

    private var welcome: some View {
        GeometryReader { viewport in
            ScrollView {
                VStack(spacing: 22) {
                    Wordmark(width: min(viewport.size.width * 0.79, 460))
                        .foregroundStyle(theme.accent)
                        .rotationEffect(.degrees(logoRevealed || reduceMotion ? 0 : -8))
                        .scaleEffect(logoRevealed || reduceMotion ? 1 : 0.55)
                        .offset(y: logoRevealed || reduceMotion ? 0 : 24)
                        .opacity(logoRevealed ? 1 : 0)
                    VStack(spacing: 8) {
                        Text("Close the lid. Keep working.")
                            .font(.system(size: 35, weight: .bold, design: .rounded))
                            .accessibilityAddTraits(.isHeader)
                        Text("Keep your Mac awake, dim the display, and reconnect when Wi-Fi drops.")
                            .font(.system(size: 15))
                            .foregroundStyle(theme.muted)
                    }
                    .multilineTextAlignment(.center)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Choose your theme").font(.headline).accessibilityAddTraits(.isHeader)
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 10) {
                                ForEach(AppTheme.allCases) { themeChoice($0).frame(minWidth: 132) }
                            }
                            VStack(spacing: 8) {
                                ForEach(AppTheme.allCases) { themeChoice($0) }
                            }
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: 525)
                    .modifier(FogPanel())
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, minHeight: viewport.size.height)
            }
        }
    }

    private func themeChoice(_ option: AppTheme) -> some View {
        let selected = themeID == option.rawValue
        return Button {
            guard !selected else { return }
            if option != theme, !reduceMotion, let previousFrame = captureThemeFrame() {
                inkTransition = ThemeInkTransition(previousFrame: previousFrame, destination: option)
            }
            themeID = option.rawValue
        } label: {
            HStack(spacing: 8) {
                ThemeSwatch(theme: option, selected: selected)
                    .frame(width: 22, height: 22)
                    .anchorPreference(key: ThemeSwatchAnchors.self, value: .bounds) { [option: $0] }
                Text(option.name).font(.system(size: 13, weight: .semibold))
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(option.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(option.paper, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(selected ? option.accent : option.line, lineWidth: selected ? 2 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var bottomRail: some View {
        HStack {
            Button("Back") { move(-1) }
                .buttonStyle(InkButton(prominent: false))
                .disabled(model.step == 0)
            Spacer()
            HStack(spacing: 7) {
                ForEach(0..<5) { index in
                    Capsule().fill(index == model.step ? theme.accent : theme.line)
                        .frame(width: index == model.step ? 23 : 7, height: 5)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(model.step + 1) of 5")
            .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: model.step)
            Spacer()
            Button(model.step == 4 ? "Finish" : "Continue") {
                if model.step == 4 { model.finish?() }
                else { move(1) }
            }
            .buttonStyle(InkButton())
            .disabled(model.step == 0 && AppTheme(rawValue: themeID) == nil)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func move(_ delta: Int) {
        inkTransition = nil
        model.move(delta)
    }
}

// Pages share one sliding track; each retains its scroll position and content.
private struct TourPage: View {
    @ObservedObject var model: OnboardingModel
    let step: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appTheme) private var theme
    private let titles = ["Close the lid.\nKeep things going.", "A shortcut you won’t\ntype by accident.", "Lights down.\nWork still running.", "Wi-Fi left?\nBring your own.", "We live up here."]
    private var bodies: [String] { [
        "Keep your Mac awake, dim its display when the lid closes, and reconnect to your hotspot when Wi-Fi drops. Open Archaive from the Dock to manage these settings.",
        "\(model.shortcut.label) toggles keep awake. Click the keys to record your own combination, here or in Keep Awake.\n\nApprove administrator access once. After that, toggles need no password.",
        "With keep awake enabled, closing the lid brings supported displays to zero brightness. Open it again and your previous brightness returns.\n\nArchaive doesn’t request screen sleep or lock. Your Mac’s other lock settings still apply. Keyboard lighting is unchanged.",
        "Set your hotspot’s exact Wi-Fi name, emoji included. Archaive waits for Wi-Fi to drop, then tries your hotspot. Keep it nearby and discoverable.\n\nUse Custom Password is useful for a non-Apple hotspot, or whenever macOS normally asks for a password. If macOS already remembers it, leave the toggle off.",
        "The menu bar gives you quick access.\n\nMoon means normal sleep. Sun means keep awake. The Archaive window has all your controls."
    ] }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 38) {
                        copy.frame(width: 360)
                        stage.frame(width: 370)
                    }
                    VStack(alignment: .leading, spacing: 24) { copy; stage }.frame(maxWidth: 450)
                }
                .padding(.vertical, 32)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(titles[step]).font(.system(size: 44, weight: .bold, design: .rounded)).fixedSize(horizontal: false, vertical: true)
            Text(bodies[step]).font(.system(size: 16)).foregroundStyle(theme.muted).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
            if step == 2 { Text("An awake Mac uses battery and produces heat. Keep it ventilated and out of your bag.").font(.callout).foregroundStyle(theme.muted) }
        }
    }

    @ViewBuilder private var stage: some View {
        VStack(spacing: step == 1 ? 20 : 24) {
            if step == 1 {
                TourSleepSymbol(progress: model.awake ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: model.awake)
                    .accessibilityLabel(model.awake ? "Keep awake on" : "Keep awake off")
                Text(model.awake ? "Mac stays awake" : "Mac sleeps normally").font(.system(size: 24, weight: .semibold, design: .rounded))
                Text("We chose ⌃⌥⌘K because it’s hard to press by accident. Feel free to change it.")
                    .font(.system(size: 13)).foregroundStyle(theme.muted)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 10) {
                    ShortcutRecorder(shortcut: model.shortcut, keySize: 38,
                        save: { model.saveShortcut?($0) },
                        recordingChanged: { model.recordingChanged?($0) })
                        .frame(height: 38)
                    Text("Click to edit · Press your shortcut · Esc to cancel")
                        .font(.system(size: 12)).foregroundStyle(theme.muted)
                }
                VStack(spacing: 12) {
                    Button("Try the toggle") { model.toggleSleep() }.buttonStyle(InkButton())
                    Text(model.practiced ? "That’s it. Only the preview changed." : "Practice here without changing your Mac.")
                        .font(.system(size: 12)).foregroundStyle(theme.accent)
                }
                Divider()
                VStack(spacing: 12) {
                    if model.authorizationReady {
                        Label("Administrator access approved", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .medium)).foregroundStyle(theme.accent)
                    } else {
                        Button("Approve Once") { model.authorize?() }
                            .buttonStyle(InkButton()).disabled(model.authorizationBusy)
                        Text(model.authorizationStatus).font(.system(size: 13)).foregroundStyle(theme.accent).multilineTextAlignment(.center)
                    }
                    Text("Allows only the keep-awake on/off commands without a password. No password is stored. Remove access from the menu after restoring sleep.")
                        .font(.system(size: 12)).foregroundStyle(theme.muted).multilineTextAlignment(.center)
                }
            } else if step == 2 {
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(model.lidClosed ? Color.black : theme.wash.opacity(0.45)).frame(height: 190)
                    VStack(spacing: 12) {
                        Image(systemName: "laptopcomputer").font(.system(size: 64))
                        Text(model.lidClosed ? "Brightness 0% · still awake" : "Your brightness · restored").font(.system(size: 13, design: .monospaced))
                    }.foregroundStyle(model.lidClosed ? .white.opacity(0.65) : theme.ink)
                }
                .animation(.easeInOut(duration: reduceMotion ? 0.14 : 0.42), value: model.lidClosed)
                Button(model.lidClosed ? "Open the preview lid" : "Close the preview lid") { model.lidClosed.toggle() }.buttonStyle(InkButton())
                Text("Simulation. Your actual display stays unchanged.").font(.system(size: 12)).foregroundStyle(theme.muted)
            } else if step == 3 {
                Image(systemName: "personalhotspot").font(.system(size: 65)).foregroundStyle(theme.accent)
                Text("One less dropped connection.").font(.system(size: 25, weight: .semibold, design: .rounded)).multilineTextAlignment(.center)
                Button("Set Up My Hotspot") { model.setup?() }.buttonStyle(InkButton())
                Text(model.setupStatus).font(.system(size: 14)).foregroundStyle(theme.accent).multilineTextAlignment(.center).accessibilityAddTraits(.updatesFrequently)
                Text("Custom passwords are stored in Keychain. Setting one may also update macOS’s saved Wi-Fi password.").font(.system(size: 12)).foregroundStyle(theme.muted).multilineTextAlignment(.center)
            } else {
                HStack(spacing: 24) {
                    previewIcon(awake: false)
                    previewIcon(awake: true)
                }
                Text(model.actualBusy ? "Updating sleep setting…" : model.actualAwake.map { $0 ? "Mac stays awake" : "Mac sleeps normally" } ?? "Checking sleep setting…")
                    .font(.system(size: 13)).foregroundStyle(theme.accent)
                if !model.authorizationReady {
                    Text(model.authorizationStatus).font(.system(size: 12)).foregroundStyle(theme.muted).multilineTextAlignment(.center)
                }
                Text("Right here.\nWhenever you need it.").font(.system(size: 29, weight: .bold, design: .rounded)).multilineTextAlignment(.center)
                if model.target == nil {
                    Text("Reveal the menu bar at the top of this screen to find Archaive. It may be hidden by your notch or menu bar manager.").font(.system(size: 14)).multilineTextAlignment(.center)
                    Button("Find the icon again") { model.locate?() }.buttonStyle(.plain)
                }
                Text("Replay any time from Welcome Tour in Archaive.").font(.system(size: 12)).foregroundStyle(theme.muted)
            }
        }.padding(28).frame(maxWidth: .infinity)
            .modifier(FogPanel())
    }

    private func previewIcon(awake: Bool) -> some View {
        Button { model.selectSleepMode(awake: awake) } label: {
            TourSleepSymbol(progress: awake ? 1 : 0)
                .opacity(model.actualAwake == awake ? 1 : 0.45)
                .animation(.easeOut(duration: 0.15), value: model.actualAwake)
        }
        .disabled(model.actualBusy || model.actualAwake == nil)
        .buttonStyle(TourIconButton())
        .accessibilityLabel(awake ? "Keep this Mac awake" : "Restore normal sleep")
        .accessibilityValue(model.actualAwake == awake ? "Selected" : "Not selected")
        .accessibilityAddTraits(model.actualAwake == awake ? .isSelected : [])
        .help("Select this Mac’s sleep mode.")
    }

}

private struct TourSleepSymbol: View, Animatable {
    var progress: CGFloat
    @Environment(\.appTheme) private var theme

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Image(nsImage: StatusIconAnimator.image(progress: progress, description: "", size: 72))
            .renderingMode(.template)
            .foregroundStyle(theme.accent)
            .frame(width: 72, height: 72)
    }
}

private struct TourIconButton: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? 0.86 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(reduceMotion ? .easeOut(duration: 0.1) : .spring(response: 0.28, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

private struct MenuBarPointer: Shape {
    let target: CGPoint

    func path(in rect: CGRect) -> Path {
        let tip = CGPoint(x: target.x, y: max(30, target.y + 16))
        let direction: CGFloat = tip.x > rect.midX ? -1 : 1
        var path = Path()
        path.move(to: CGPoint(x: tip.x + 62 * direction, y: tip.y + 49))
        path.addQuadCurve(to: tip, control: CGPoint(x: tip.x, y: tip.y + 44))
        path.move(to: CGPoint(x: tip.x - 8, y: tip.y + 10))
        path.addLine(to: tip)
        path.addLine(to: CGPoint(x: tip.x + 8, y: tip.y + 10))
        return path
    }
}
