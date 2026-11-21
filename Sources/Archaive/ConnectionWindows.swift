import SwiftUI

private struct ConnectionWindow<Content: View>: View {
    @AppStorage(AppTheme.storageKey) private var theme = AppTheme.defaultTheme
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 31, weight: .bold, design: .rounded))
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle).foregroundStyle(theme.muted).fixedSize(horizontal: false, vertical: true)
                }
                content()
            }
            .padding(26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background { ThemeCanvas(theme: theme) }
        .foregroundStyle(theme.ink)
        .tint(theme.accent)
        .environment(\.appTheme, theme)
        .environment(\.colorScheme, .light)
    }
}

struct HotspotSettingsView: View {
    @State var name: String
    @State var useCustomPassword: Bool
    @State private var password = ""
    @State private var error: String?
    @FocusState private var nameFocused: Bool
    let save: (String, Bool, String) -> String?
    let cancel: () -> Void

    var body: some View {
        ConnectionWindow(title: "Your hotspot", subtitle: "Archaive tries this network when Wi-Fi drops.") {
            VStack(alignment: .leading, spacing: 13) {
                Text("Hotspot Wi-Fi name").font(.headline)
                HStack {
                    TextField("Exact Wi-Fi name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .focused($nameFocused)
                        .accessibilityLabel("Hotspot Wi-Fi name")
                    Button {
                        nameFocused = true
                        NSApp.orderFrontCharacterPalette(nil)
                    } label: {
                        Image(systemName: "face.smiling")
                    }
                    .buttonStyle(InkButton(prominent: false))
                    .help("Emoji and Symbols")
                    .accessibilityLabel("Emoji and Symbols")
                }
                Toggle("Use Custom Password", isOn: $useCustomPassword).toggleStyle(.switch)
                if useCustomPassword {
                    SecureField("Leave blank to keep a stored password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Custom hotspot password")
                    Text("Stored in Keychain. Joining may also update the Wi-Fi password saved by macOS.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    Text("Uses the Wi-Fi password already saved by macOS.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.callout).foregroundStyle(Color(nsColor: .systemRed))
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }
            .padding(18)
            .modifier(FogPanel())
            HStack {
                Button("Cancel", action: cancel)
                    .buttonStyle(InkButton(prominent: false)).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save & Enable") {
                    error = save(name, useCustomPassword, password)
                    if error == nil { password = "" }
                }
                .buttonStyle(InkButton()).keyboardShortcut(.defaultAction)
            }
        }
        .onAppear { nameFocused = true }
        .onChange(of: useCustomPassword) { _ in error = nil }
        .onDisappear { password = "" }
    }
}

final class ShareWindowState: ObservableObject {
    @Published var links: [String] = []
    @Published var qr: NSImage?
    @Published var active = false
    @Published var starting = false
}

struct ScreenSharingView: View {
    @ObservedObject var state: ShareWindowState
    let toggleShare: () -> Void
    let copyLink: () -> Void

    private var status: String {
        if state.starting { return "Waiting for screen-capture permission…" }
        if !state.active { return "Start sharing to create a session link." }
        if state.links.isEmpty { return "No local IPv4 address. Connect to Wi-Fi, then stop and restart sharing." }
        return "Sharing is active"
    }

    var body: some View {
        ConnectionWindow(title: "Share Screen to Phone", subtitle: "Connect both devices to the same Wi-Fi or hotspot. Scan the code in the Archaive iPhone app, or open a sharing link in your phone’s browser.") {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(status).font(.headline).accessibilityAddTraits(.updatesFrequently)
                    ForEach(state.links, id: \.self) { link in
                        Text(link).textSelection(.enabled).font(.system(.callout, design: .monospaced))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let qr = state.qr {
                    Image(nsImage: qr)
                        .resizable().interpolation(.none).scaledToFit()
                        .frame(width: 116, height: 116)
                        .accessibilityLabel("Phone sharing QR code")
                }
            }
            .padding(18)
            .modifier(FogPanel())
            Text("View only. Anyone with the link can see your screen over this unencrypted local connection. Use a trusted network. Locking your Mac stops sharing.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Copy Link", action: copyLink)
                    .buttonStyle(InkButton(prominent: false))
                    .disabled(state.links.isEmpty)
                Spacer()
                Button(state.active || state.starting ? "Stop Sharing" : "Start Sharing", action: toggleShare)
                    .buttonStyle(InkButton())
            }
        }
    }
}
