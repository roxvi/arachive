import AppKit
import SwiftUI
import QuartzCore

final class OnboardingModel: NSObject, ObservableObject {
    @Published var shortcut = Shortcut.load()
    @Published var step = 0
    @Published var forward = true
    @Published var awake = false
    @Published var dim = true
    @Published var hotspot = false
    @Published var lidClosed = false
    @Published var practiced = false
    @Published var setupStatus = "Optional. You can set this up later from the menu."
    @Published var authorizationStatus = "Approve once. Future keep-awake toggles need no password."
    @Published var authorizationBusy = false
    @Published var authorizationReady = false
    var customizeShortcut: (() -> Void)?
    var authorize: (() -> Void)?
    @Published var target: CGPoint?
    var finish: (() -> Void)?
    var openMenu: (() -> Void)?
    var setup: (() -> Void)?
    var locate: (() -> Void)?

    func move(_ delta: Int) {
        forward = delta > 0
        step = min(4, max(0, step + delta))
        if step == 4 { locate?() }
    }
    @objc func toggleSleep() { awake.toggle(); practiced = true }
    @objc func toggleDimming() { dim.toggle() }
    @objc func toggleHotspot() { hotspot.toggle() }
    @objc func configureHotspot() { setupStatus = "Preview only. Set up your real hotspot in step 4." }
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
    var previewMenu: ((OnboardingModel) -> NSMenu)?
    var setup: (() -> Void)?
    var statusButton: (() -> NSStatusBarButton?)?
    var handoff: (() -> Void)?
    var customizeShortcut: (() -> Void)?
    var authorize: (() -> Void)?
    var authorized: (() -> Bool)?
    private var escaping: Any?

    func present() {
        guard window == nil else { window?.makeKeyAndOrderFront(nil); return }
        guard let screen = statusButton?()?.window?.screen ?? NSApp.keyWindow?.screen ?? NSScreen.main else { return }
        previousWindow = NSApp.keyWindow
        model = OnboardingModel()
        model.authorizationReady = authorized?() ?? false
        if model.authorizationReady { model.authorizationStatus = "Already approved. Toggles need no password." }
        model.authorize = { [weak self] in self?.authorize?() }
        model.customizeShortcut = { [weak self] in
            guard let self else { return }
            self.window?.level = .normal
            self.customizeShortcut?()
            self.window?.level = .floating
            self.window?.makeKeyAndOrderFront(nil)
        }
        let panel = TakeoverWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        model.finish = { [weak self] in self?.dismiss() }
        model.openMenu = { [weak self] in self?.showPreviewMenu() }
        model.setup = { [weak self] in
            guard let self else { return }
            self.model.setupStatus = "Hotspot Settings is open. Save to enable, or close it to skip."
            self.window?.level = .normal
            self.setup?()
        }
        model.locate = { [weak self] in self?.locateIcon() }
        panel.contentView = NSHostingView(rootView: OnboardingView(model: model))
        window = panel
        escaping = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true else { return event }
            if event.keyCode == 53 { self.dismiss(); return nil }
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
        if model.step == 1 { model.toggleSleep() }
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

    private func showPreviewMenu() {
        guard let window, let view = window.contentView, let menu = previewMenu?(model) else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: view.bounds.midX + 80, y: view.bounds.midY + 90), in: view)
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
        guard let panel = window else { return }
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

private struct Backdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let cyan = Color(red: 0.43, green: 0.88, blue: 0.94)

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Backdrop()
                Color.black.opacity(0.77)
                RadialGradient(colors: [cyan.opacity(0.13), .clear], center: .trailing, startRadius: 0, endRadius: 700)
                if model.step == 4, let target = model.target {
                    MenuBarArrows(target: target).allowsHitTesting(false).accessibilityHidden(true)
                }
                VStack(spacing: 20) {
                    HStack {
                        Spacer()
                        Text(String(format: "%02d / 05", model.step + 1)).font(.system(size: 13, design: .monospaced)).foregroundStyle(.white.opacity(0.65))
                        Button("Skip") { model.finish?() }.buttonStyle(.plain).padding(.leading, 20)
                    }.padding(.top, 24)
                    GeometryReader { viewport in
                        HStack(spacing: 0) {
                            ForEach(0..<5) { step in
                                TourPage(model: model, step: step)
                                    .frame(width: viewport.size.width, height: viewport.size.height)
                            }
                        }
                        .offset(x: -CGFloat(model.step) * viewport.size.width)
                        .animation(reduceMotion ? nil : .timingCurve(0.22, 0.8, 0.24, 1, duration: 0.7), value: model.step)
                        .frame(width: viewport.size.width, alignment: .leading)
                    }
                    .clipped()
                    HStack {
                        Button("Back") { advance(-1) }.disabled(model.step == 0).buttonStyle(.plain)
                        Spacer()
                        HStack(spacing: 8) {
                            ForEach(0..<5) { index in
                                Capsule().fill(index == model.step ? cyan : .white.opacity(0.22)).frame(width: index == model.step ? 28 : 8, height: 5)
                            }
                        }.accessibilityLabel("Step \(model.step + 1) of 5")
                        Spacer()
                        Button(model.step == 4 ? "Got it. Open the menu." : "Continue") {
                            if model.step == 4 { model.finish?() } else { advance(1) }
                        }.buttonStyle(TourButton()).frame(width: 225, alignment: .trailing).keyboardShortcut(.defaultAction)
                    }.padding(.bottom, 8)
                }.padding(.horizontal, geometry.size.width < 600 ? 20 : 32).padding(.bottom, 24)
            }.foregroundStyle(.white).preferredColorScheme(.dark)
        }
    }

    private func advance(_ delta: Int) { model.move(delta) }
}

// Pages share one sliding track; each retains its scroll position and content.
private struct TourPage: View {
    @ObservedObject var model: OnboardingModel
    let step: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let cyan = Color(red: 0.43, green: 0.88, blue: 0.94)
    private let titles = ["Close the lid.\nKeep things going.", "A shortcut you won’t\ntype by accident.", "Lights down.\nWork still running.", "Wi-Fi left?\nBring your own.", "We live up here."]
    private var bodies: [String] { [
        "Keep your Mac awake, dim its display when the lid closes, and reconnect to your hotspot when Wi-Fi drops. All from one tiny menu.",
        "It’s an important setting, so we made the keybind hard to accidentally type 😉\n\n\(model.shortcut.label) toggles keep awake. Customize it below or later from Keyboard Shortcut… in the menu. Approve administrator access once below. After that, toggles need no password.",
        "With keep awake enabled, closing the lid brings supported displays to zero brightness. Open it again and your previous brightness returns.\n\nArchaive doesn’t request screen sleep or lock. Your Mac’s other lock settings still apply. Keyboard lighting is unchanged.",
        "Set your hotspot’s exact Wi-Fi name, emoji included. Archaive waits for Wi-Fi to drop, then tries your hotspot. Keep it nearby and discoverable.\n\nUse Custom Password is useful for a non-Apple hotspot, or whenever macOS normally asks for a password. If macOS already remembers it, leave the toggle off.",
        "The menu bar. That’s the whole app.\n\nMoon means normal sleep. Sun means keep awake. Click it whenever you need us."
    ] }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 56) {
                        copy.frame(width: 410)
                        stage.frame(width: 390)
                    }.frame(minWidth: 856)
                    VStack(alignment: .leading, spacing: 28) { copy; stage }
                }
                .padding(.vertical, 32)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
        .disabled(step != model.step)
        .allowsHitTesting(step == model.step)
        .accessibilityHidden(step != model.step)
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(["MEET ARCHAIVE", "TRY IT SAFELY", "FULL DIM, STILL AWAKE", "YOUR FIRST SETUP", "ALWAYS WITHIN REACH"][step])
                .font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(cyan)
            Text(titles[step]).font(.system(size: 44, weight: .bold, design: .rounded)).fixedSize(horizontal: false, vertical: true)
            Text(bodies[step]).font(.system(size: 16)).foregroundStyle(.white.opacity(0.78)).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
            if step == 0 { Text("An awake Mac still uses battery and produces heat. Don’t put it in a bag while keep awake is on.").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)) }
        }
    }

    @ViewBuilder private var stage: some View {
        VStack(spacing: 24) {
            if step <= 1 {
                Label("LIVE MENU PREVIEW", systemImage: "cursorarrow.click").font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(cyan)
                ZStack {
                    Image(systemName: "moon.fill").opacity(model.awake ? 0 : 1)
                    Image(systemName: "sun.max.fill").foregroundStyle(cyan).opacity(model.awake ? 1 : 0)
                }
                .font(.system(size: 65))
                .frame(width: 90, height: 80)
                .scaleEffect(reduceMotion || !model.awake ? 1 : 1.06)
                .animation(.easeInOut(duration: reduceMotion ? 0.12 : 0.28), value: model.awake)
                .accessibilityLabel(model.awake ? "Keep awake on" : "Keep awake off")
                Text(model.awake ? "Mac stays awake" : "Mac sleeps normally").font(.system(size: 24, weight: .semibold, design: .rounded))
                if step == 1 {
                    HStack(spacing: 8) {
                        ForEach(model.shortcut.symbols, id: \.self) { key in
                            Text(key).font(.system(size: 29, weight: .medium)).frame(width: 58, height: 58).background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }.accessibilityLabel(model.shortcut.label)
                    Button("Customize shortcut…") { model.customizeShortcut?() }.buttonStyle(.plain)
                    Button("Try the toggle") { model.toggleSleep() }.buttonStyle(TourButton())
                    Button("Open interactive menu") { model.openMenu?() }.buttonStyle(.plain)
                    Divider()
                    Button(model.authorizationReady ? "Administrator Setup Complete" : "Approve Once") { model.authorize?() }
                        .buttonStyle(TourButton()).disabled(model.authorizationBusy || model.authorizationReady)
                    Text(model.authorizationStatus).font(.system(size: 13)).foregroundStyle(cyan).multilineTextAlignment(.center)
                    Text("Allows your macOS user to run only the two keep-awake on/off commands without a password. No password is stored. Remove access from the menu anytime after restoring sleep.")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.65)).multilineTextAlignment(.center)
                    Text(model.practiced ? "That’s it. Only the preview changed." : "Press the shortcut, or use the button.").font(.system(size: 13)).foregroundStyle(cyan)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Toggle Keep Awake     \(model.shortcut.label)", systemImage: "sun.max")
                        Label("Fully Dim When Lid Closes", systemImage: "display")
                        Divider()
                        Label("Auto-Connect to Hotspot", systemImage: "wifi")
                        Label("Hotspot Settings…", systemImage: "gearshape")
                    }.font(.system(size: 14))
                }
                Text("Practice changes only the preview. Approve Once installs real toggle permission.").font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
            } else if step == 2 {
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(model.lidClosed ? Color.black : cyan.opacity(0.22)).frame(height: 190)
                    VStack(spacing: 12) {
                        Image(systemName: "laptopcomputer").font(.system(size: 64))
                        Text(model.lidClosed ? "Brightness 0% · still awake" : "Your brightness · restored").font(.system(size: 13, design: .monospaced))
                    }.foregroundStyle(model.lidClosed ? .white.opacity(0.35) : .white)
                }
                .animation(.easeInOut(duration: reduceMotion ? 0.14 : 0.42), value: model.lidClosed)
                Button(model.lidClosed ? "Open the preview lid" : "Close the preview lid") { model.lidClosed.toggle() }.buttonStyle(TourButton())
                Text("Simulation. Your actual display stays unchanged.").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
            } else if step == 3 {
                Image(systemName: "personalhotspot").font(.system(size: 65)).foregroundStyle(cyan)
                Text("One less dropped connection.").font(.system(size: 25, weight: .semibold, design: .rounded)).multilineTextAlignment(.center)
                Button("Set Up My Hotspot") { model.setup?() }.buttonStyle(TourButton())
                Text(model.setupStatus).font(.system(size: 14)).foregroundStyle(cyan).multilineTextAlignment(.center).accessibilityAddTraits(.updatesFrequently)
                Text("Custom passwords are stored in Keychain. Setting one may also update macOS’s saved Wi-Fi password.").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.center)
            } else {
                HStack(spacing: 24) {
                    Image(systemName: "moon.fill")
                    Image(systemName: "sun.max.fill").foregroundStyle(cyan)
                }.font(.system(size: 54))
                Text("Right here.\nWhenever you need it.").font(.system(size: 29, weight: .bold, design: .rounded)).multilineTextAlignment(.center)
                if model.target == nil {
                    Text("Reveal the menu bar at the top of this screen to find Archaive. It may be hidden by your notch or menu bar manager.").font(.system(size: 14)).multilineTextAlignment(.center)
                    Button("Find the icon again") { model.locate?() }.buttonStyle(.plain)
                }
                Text("Replay any time: menu → Replay Welcome Tour.").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
            }
        }.padding(28).frame(maxWidth: .infinity)
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.12), lineWidth: 1))
    }
}

private struct TourButton: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 14, weight: .semibold)).foregroundStyle(.black)
            .padding(.horizontal, 22).padding(.vertical, 13)
            .background(Color(red: 0.65, green: 0.94, blue: 0.97).opacity(configuration.isPressed ? 0.75 : 1), in: Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct MenuBarArrows: View {
    let target: CGPoint

    var body: some View {
        Canvas { context, size in
            // Match the reference: a solid red shaft with a broad triangular head.
            for index in 0..<12 {
                let column = CGFloat(index % 6)
                let row = CGFloat(index / 6)
                let start = CGPoint(
                    x: 30 + (column + row * 0.25) / 5.25 * max(0, size.width - 60),
                    y: 100 + row * 85
                )
                let dx = target.x - start.x
                let dy = target.y - start.y
                let distance = hypot(dx, dy)
                let length = min(160, distance - 30)
                guard length > 35 else { continue }
                let halfHeight = length * 0.178
                let halfShaft = halfHeight * 0.45
                let neck = length * 0.69
                var arrow = Path()
                arrow.move(to: CGPoint(x: 0, y: -halfShaft))
                arrow.addLine(to: CGPoint(x: neck, y: -halfShaft))
                arrow.addLine(to: CGPoint(x: neck, y: -halfHeight))
                arrow.addLine(to: CGPoint(x: length, y: 0))
                arrow.addLine(to: CGPoint(x: neck, y: halfHeight))
                arrow.addLine(to: CGPoint(x: neck, y: halfShaft))
                arrow.addLine(to: CGPoint(x: 0, y: halfShaft))
                arrow.closeSubpath()
                var drawing = context
                drawing.translateBy(x: start.x, y: start.y)
                drawing.rotate(by: .radians(atan2(dy, dx)))
                drawing.fill(arrow, with: .color(Color(red: 1, green: 0, blue: 0)))
            }
        }
    }
}
