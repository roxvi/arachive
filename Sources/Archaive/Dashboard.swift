import SwiftUI

enum DashboardPage: String, CaseIterable, Identifiable {
    case power = "Keep Awake"
    case connection = "Connections"

    var id: Self { self }

    var symbol: String {
        switch self {
        case .power: return "sun.max"
        case .connection: return "personalhotspot"
        }
    }
}

final class DashboardState: ObservableObject {
    struct Status: Equatable {
        var awake: Bool?
        var busy = false
        var dim = true
        var authorized = false
        var canRestore = false
        var shortcut = Shortcut.standard
        var shortcutAvailable = true
        var hotspotName: String?
        var hotspotEnabled = false
        var network = "Checking Wi-Fi…"
        var sharing = false
        var startingShare = false
    }

    @Published var page: DashboardPage = .power
    @Published var status = Status()
}

struct DashboardActions {
    let addApps: () -> Void
    let toggleSleep: () -> Void
    let toggleDimming: () -> Void
    let setupSleepAccess: () -> Void
    let removeSleepAccess: () -> Void
    let restoreSleep: () -> Void
    let saveShortcut: (Shortcut) -> String?
    let recordingShortcut: (Bool) -> Void
    let configureHotspot: () -> Void
    let toggleHotspot: () -> Void
    let configureShare: () -> Void
    let stopShare: () -> Void
    let replayTour: () -> Void
    let captureThemeFrame: () -> NSImage?
}

struct Dashboard: View {
    @ObservedObject var state: DashboardState
    @ObservedObject var focus: FocusSession
    let actions: DashboardActions
    @State private var search = ""
    @State private var showFocusSettings = false

    @AppStorage(AppTheme.storageKey) private var theme = AppTheme.defaultTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spread: ThemeInkTransition?

    private var status: DashboardState.Status { state.status }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                Group {
                    switch state.page {
                    case .power: powerPage
                    case .connection: connectionsPage
                    }
                }
                .frame(maxWidth: 1020)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 30)
                .padding(.top, 6)
                .padding(.bottom, 28)
                .id(state.page)
                .transition(.opacity)
            }
            footer
        }
        .frame(minWidth: 640, minHeight: 475)
        .background { ThemeCanvas(theme: theme, showsOutline: false) }
        .themeInkTransition($spread)
        .ignoresSafeArea(.container, edges: .top)
        .environment(\.appTheme, theme)
        .environment(\.colorScheme, .light)
        .foregroundStyle(theme.ink)
        .tint(theme.accent)
    }

    private var header: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Wordmark(width: 147)
                    .foregroundStyle(theme.accent)
                    .padding(.bottom, 13)
                Text(state.page.rawValue)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .tracking(-1.3)
                    .accessibilityAddTraits(.isHeader)
                Text(pageSummary)
                    .font(.system(size: 14))
                    .foregroundStyle(theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 150)
        }
        .padding(.horizontal, 30)
        .padding(.top, 28)
        .frame(maxWidth: 1080)
        .frame(maxWidth: .infinity, minHeight: 165)
        .overlay(alignment: .topTrailing) { navigation }
    }

    private var pageSummary: String {
        switch state.page {
        case .power: "Control sleep, the lid display, and which apps stay active."
        case .connection: "Stay online with hotspot fallback or share your Mac screen to a phone."
        }
    }

    private var navigation: some View {
        VStack(spacing: 4) {
            ForEach(DashboardPage.allCases) { page in
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.17)) { state.page = page }
                } label: {
                    Label(page.rawValue, systemImage: page.symbol)
                        .font(.system(size: 15, weight: state.page == page ? .bold : .medium))
                        .frame(width: 132, height: 36)
                        .background(state.page == page ? theme.wash.opacity(0.65) : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(state.page == page ? .isSelected : [])
                .accessibilityValue(page == .power && focus.active ? "Focus active" : "")
            }
        }
        .padding(.top, 24)
        .padding(.trailing, 30)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("Theme").font(.callout.weight(.semibold)).foregroundStyle(theme.muted).fixedSize()
                ForEach(AppTheme.allCases) { option in
                    Button {
                        selectTheme(option)
                    } label: {
                        HStack(spacing: 6) {
                            ThemeSwatch(theme: option, selected: option == theme)
                                .frame(width: 17, height: 17)
                                .anchorPreference(key: ThemeSwatchAnchors.self, value: .bounds) { [option: $0] }
                            Text(option.name).font(.system(size: 12, weight: .medium)).fixedSize()
                        }
                        .padding(.horizontal, 6)
                        .frame(height: 31)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(option.name)
                    .accessibilityLabel(option.name)
                    .accessibilityAddTraits(option == theme ? .isSelected : [])
                }
            }
            Spacer()
            Button(action: actions.replayTour) { Label("Welcome Tour", systemImage: "play.circle") }
                .buttonStyle(InkButton(prominent: false))
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 12)
        .background(.white.opacity(0.52))
        .overlay(alignment: .top) { Rectangle().fill(theme.line).frame(height: 1) }
    }

    private func selectTheme(_ selection: AppTheme) {
        guard theme != selection else { return }
        guard !reduceMotion, let frame = actions.captureThemeFrame() else {
            theme = selection
            spread = nil
            return
        }
        spread = ThemeInkTransition(previousFrame: frame, destination: selection)
        theme = selection
    }

    private var focusSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Focus").font(.headline)
                    Text(focusStatus).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Focus", isOn: Binding(get: { focus.enabled }, set: { value in
                    focus.setEnabled(value)
                    if value && focus.allowed.isEmpty { showFocusSettings = true }
                }))
                .labelsHidden().toggleStyle(.switch)
            }
            .padding(.top, 15)
            .padding(.bottom, 10)
            DisclosureGroup("Focus Settings", isExpanded: $showFocusSettings) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Only when the lid is closed", isOn: Binding(
                        get: { focus.closedLidOnly }, set: focus.setClosedLidOnly
                    ))
                    .toggleStyle(.switch)
                    Divider()
                    HStack {
                        Text("Apps to keep running").font(.headline)
                        Spacer()
                        Button(action: actions.addApps) { Label("Add Apps…", systemImage: "plus") }
                    }
                    TextField("Find an app", text: $search)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Find an app")
                    appList.frame(height: 150)
                    HStack(spacing: 14) {
                        Text("Apps opened during Focus")
                        Spacer(minLength: 2)
                        Picker("Apps opened during Focus", selection: Binding(get: { focus.newApps }, set: focus.setNewApps)) {
                            ForEach(NewFocusApps.allCases, id: \.self) { option in Text(option.title).tag(option) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    Text("Shared macOS services and protected apps stay running.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .padding(.top, 9)
            }
            if let message = focus.message {
                Text(message).font(.callout).foregroundStyle(.secondary)
                    .padding(.top, 9)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }

    private var focusStatus: String {
        if !focus.enabled { return "Pause other apps while Keep Awake is on." }
        if focus.allowed.isEmpty { return "Select at least one app to keep running." }
        if status.awake != true { return "Ready to start when Keep Awake turns on." }
        if focus.closedLidOnly && focus.lidClosed != true {
            return focus.lidClosed == nil ? "Lid sensor unavailable." : "Waiting for the lid to close."
        }
        if focus.active {
            let count = focus.apps.filter(\.paused).count
            return count == 1 ? "1 app paused" : "\(count) apps paused"
        }
        return "Focus is inactive."
    }

    private var appList: some View {
        let apps = focus.apps.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
        return Group {
            if apps.isEmpty {
                VStack(spacing: 5) {
                    Text(search.isEmpty ? "No eligible apps are open" : "No matching apps").font(.headline)
                    Text(search.isEmpty ? "Use Add Apps to select an installed app." : "Try a different app name.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(apps) { app in
                            HStack(spacing: 9) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: app.id))
                                    .resizable().frame(width: 25, height: 25)
                                    .accessibilityHidden(true)
                                Toggle(app.name, isOn: Binding(get: { focus.allowed.contains(app.id) },
                                                               set: { focus.setAllowed(app.id, $0) }))
                                    .toggleStyle(.checkbox)
                                Spacer(minLength: 4)
                                Text(app.paused ? "Paused" : app.running ? "Running" : "Closed")
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            Divider().padding(.leading, 43)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.wash.opacity(0.16), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private var powerPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            setting(
                status.awake.map { $0 ? "Keeping awake" : "Normal sleep" } ?? "Checking sleep",
                status.busy ? "Updating sleep setting…" : status.awake.map {
                    $0 ? "Keep Awake is on, even with the lid closed. Keep your Mac ventilated."
                       : "Turn on Keep Awake to finish work with the lid closed."
                } ?? "Reading the macOS sleep setting…"
            ) {
                Button(status.awake == true ? "Allow Sleep" : "Keep Awake", action: actions.toggleSleep)
                    .buttonStyle(InkButton())
                    .disabled(status.busy || status.awake == nil)
            }
            .padding(.horizontal, 20)
            .background(theme.wash.opacity(0.34), in: RoundedRectangle(cornerRadius: 20))
            VStack(alignment: .leading, spacing: 0) {
                focusSettings
                rule
                setting("Fully dim when the lid closes", "Restore the previous brightness when the lid opens.") {
                    Toggle("Fully dim when the lid closes", isOn: Binding(get: { status.dim }, set: { _ in actions.toggleDimming() }))
                        .labelsHidden().toggleStyle(.switch)
                }
                rule
                setting("Keyboard shortcut", status.shortcutAvailable ? "Click the keys to record a shortcut." : "Shortcut unavailable. Click the keys to change it.") {
                    ShortcutRecorder(shortcut: status.shortcut, keySize: 24, save: actions.saveShortcut,
                                     recordingChanged: actions.recordingShortcut)
                }
                rule
                setting("Password-free toggles", status.authorized ? "One-time administrator approval is installed." : "Approve once to change the macOS sleep setting.") {
                    Button(status.authorized ? "Remove Access…" : "Set Up…",
                           action: status.authorized ? actions.removeSleepAccess : actions.setupSleepAccess)
                        .buttonStyle(InkButton(prominent: false))
                        .disabled(status.busy)
                }
                if status.canRestore {
                    rule
                    setting("Previous sleep setting", "Restore the setting from before Archaive changed it.") {
                        Button("Restore", action: actions.restoreSleep)
                            .buttonStyle(InkButton(prominent: false)).disabled(status.busy)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 7)
            .modifier(FogPanel())
        }
    }

    private var connectionsPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            setting("Hotspot fallback", status.hotspotName.map { "\($0) · \(status.network)" } ?? "Choose a hotspot to reconnect when Wi-Fi drops.") {
                HStack {
                    Button("Hotspot Settings…", action: actions.configureHotspot).buttonStyle(InkButton(prominent: false))
                    Toggle("Hotspot fallback", isOn: Binding(get: { status.hotspotEnabled }, set: { _ in actions.toggleHotspot() }))
                        .labelsHidden().toggleStyle(.switch)
                }
            }
            rule
            setting("Share Screen to Phone", status.startingShare ? "Waiting for screen-capture permission…" : status.sharing ? "Screen sharing is active." : "Start a view-only session on your local network.") {
                HStack {
                    if status.sharing || status.startingShare { Button("Stop Sharing", action: actions.stopShare).buttonStyle(InkButton(prominent: false)) }
                    Button(status.sharing ? "Show QR Code…" : "Open Sharing…", action: actions.configureShare).buttonStyle(InkButton())
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 6)
        .modifier(FogPanel())
    }

    private var rule: some View {
        Rectangle().fill(theme.line).frame(height: 1)
    }

    private func setting<Control: View>(_ title: String, _ detail: String, @ViewBuilder control: () -> Control) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                settingCopy(title, detail).frame(minWidth: 190, alignment: .leading)
                Spacer(minLength: 0)
                control().fixedSize()
            }
            VStack(alignment: .leading, spacing: 10) {
                settingCopy(title, detail)
                control()
            }
        }
        .padding(.vertical, 15)
    }

    private func settingCopy(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(detail).foregroundStyle(theme.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
}
