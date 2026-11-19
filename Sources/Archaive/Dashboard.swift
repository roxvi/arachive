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
}

struct Dashboard: View {
    @ObservedObject var state: DashboardState
    @ObservedObject var focus: FocusSession
    let actions: DashboardActions
    @State private var search = ""
    @State private var showFocusSettings = false

    private var status: DashboardState.Status { state.status }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            Group {
                switch state.page {
                case .power: powerPage
                case .connection: connectionsPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 680, minHeight: 480)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 9) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 29, height: 29)
                    .accessibilityHidden(true)
                Text("Archaive").font(.system(size: 17, weight: .semibold))
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 19)
            ForEach(DashboardPage.allCases) { page in
                Button {
                    state.page = page
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: page.symbol).frame(width: 19)
                        Text(page.rawValue)
                        Spacer(minLength: 0)
                        if page == .power && focus.active {
                            Circle().fill(Color(nsColor: .systemGreen)).frame(width: 6, height: 6)
                                .accessibilityHidden(true)
                        }
                    }
                    .font(.system(size: 13, weight: state.page == page ? .semibold : .regular))
                    .padding(.horizontal, 9).padding(.vertical, 8)
                    .background(state.page == page ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.15) : .clear,
                                in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(state.page == page ? .isSelected : [])
                .accessibilityValue(page == .power && focus.active ? "Focus active" : "")
            }
            Spacer()
            Button(action: actions.replayTour) {
                Label("Welcome Tour", systemImage: "questionmark.circle")
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 20)
        .frame(width: 174)
        .background(Color(nsColor: .controlBackgroundColor))
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
            Divider().padding(.top, 15)
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
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private var powerPage: some View {
        settingsPage("Keep Awake", "Manage sleep, the lid display, and your keyboard shortcut.") {
            setting("Sleep", status.busy ? "Updating sleep setting…" : status.awake.map {
                $0 ? "Your Mac stays awake, including with the lid closed." : "Your Mac sleeps normally."
            } ?? "Reading the macOS sleep setting…") {
                Button(status.awake == true ? "Allow Sleep" : "Keep Awake", action: actions.toggleSleep)
                    .buttonStyle(.borderedProminent)
                    .disabled(status.busy || status.awake == nil)
            }
            focusSettings
            setting("Fully dim when the lid closes", "Restore the previous brightness when the lid opens.") {
                Toggle("Fully dim when the lid closes", isOn: Binding(get: { status.dim }, set: { _ in actions.toggleDimming() }))
                    .labelsHidden().toggleStyle(.switch)
            }
            setting("Keyboard shortcut", status.shortcutAvailable ? "Click the keys to record a shortcut." : "Shortcut unavailable. Click the keys to change it.") {
                ShortcutRecorder(shortcut: status.shortcut, keySize: 24, save: actions.saveShortcut,
                                 recordingChanged: actions.recordingShortcut)
            }
            setting("Password-free toggles", status.authorized ? "One-time administrator approval is installed." : "Approve once to change the macOS sleep setting.") {
                Button(status.authorized ? "Remove Access…" : "Set Up…",
                       action: status.authorized ? actions.removeSleepAccess : actions.setupSleepAccess)
                    .disabled(status.busy)
            }
            if status.canRestore {
                setting("Previous sleep setting", "Restore the setting from before Archaive changed it.") {
                    Button("Restore", action: actions.restoreSleep).disabled(status.busy)
                }
            }
        }
    }

    private var connectionsPage: some View {
        settingsPage("Connections", "Set up Wi-Fi fallback and share your Mac screen to a phone.") {
            setting("Hotspot fallback", status.hotspotName.map { "\($0) · \(status.network)" } ?? "Choose a hotspot to reconnect when Wi-Fi drops.") {
                HStack {
                    Button("Hotspot Settings…", action: actions.configureHotspot)
                    Toggle("Hotspot fallback", isOn: Binding(get: { status.hotspotEnabled }, set: { _ in actions.toggleHotspot() }))
                        .labelsHidden().toggleStyle(.switch)
                }
            }
            setting("Share Screen to Phone", status.startingShare ? "Waiting for screen-capture permission…" : status.sharing ? "Screen sharing is active." : "Start a view-only session on your local network.") {
                HStack {
                    if status.sharing || status.startingShare { Button("Stop Sharing", action: actions.stopShare) }
                    Button(status.sharing ? "Show QR Code…" : "Open Sharing…", action: actions.configureShare)
                }
            }
        }
    }

    private func settingsPage<Content: View>(_ title: String, _ summary: String, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heading(title, summary).padding(.bottom, 20)
                Divider()
                content()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func heading(_ title: String, _ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 32, weight: .bold)).accessibilityAddTraits(.isHeader)
            Text(summary).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func setting<Control: View>(_ title: String, _ detail: String, @ViewBuilder control: () -> Control) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                control()
            }
            .padding(.vertical, 15)
            Divider()
        }
    }
}
