import SwiftUI
import VisionKit
import AVFoundation

@main
struct ArchaivePhoneApp: App {
    var body: some Scene { WindowGroup { PhoneView() } }
}

struct PhoneView: View {
    @StateObject private var session = ScreenSession()
    @AppStorage(AppTheme.storageKey) private var theme = AppTheme.defaultTheme
    @Environment(\.scenePhase) private var phase
    @Environment(\.verticalSizeClass) private var verticalSize
    @State private var link = ""
    @State private var scanning = false
    @State private var cameraError: String?
    @State private var resetZoom = UUID()
    @State private var mode = ViewerMode.view
    @State private var isFullscreen = false
    @State private var showKeyboard = false
    @FocusState private var linkFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if session.address != nil { viewer }
                else { pairing }
            }
            .foregroundStyle(theme.ink)
            .background { theme.paper.ignoresSafeArea() }
            .toolbar(.hidden, for: .navigationBar)
        }
        .statusBarHidden(isFullscreen)
        .persistentSystemOverlays(isFullscreen ? .hidden : .automatic)
        .tint(theme.accent)
        .environment(\.appTheme, theme)
        .preferredColorScheme(.light)
        .task(id: StreamTask(address: session.address, active: phase == .active)) {
            if phase == .active, let address = session.address {
                await session.receiveFrames(from: address)
            } else { session.pause() }
        }
        .onChange(of: phase) { _, next in
            if next != .active {
                session.pause()
                mode = .view
                scanning = false
                showKeyboard = false
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
        .onChange(of: session.image != nil) { _, live in
            UIApplication.shared.isIdleTimerDisabled = live && phase == .active
            if !live { isFullscreen = false }
        }
        .onChange(of: session.controlError) { _, error in
            if error != nil { isFullscreen = false }
        }
        .onChange(of: session.canControl) { _, available in
            if !available {
                mode = .view
                showKeyboard = false
            }
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .sheet(isPresented: $scanning) {
            NavigationStack {
                QRScanner(scanned: { value in
                    scanning = false
                    connect(value)
                }, unavailable: {
                    scanning = false
                    cameraError = "The camera is unavailable. Paste the sharing link instead."
                })
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Scan your Mac’s QR code")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { scanning = false } } }
            }
        }
        .sheet(isPresented: $showKeyboard) {
            RemoteKeyboard(send: session.send)
                .environment(\.appTheme, theme)
        }
        .alert("Camera unavailable", isPresented: Binding(get: { cameraError != nil }, set: { if !$0 { cameraError = nil } })) {
            Button("OK") { cameraError = nil }
        } message: { Text(cameraError ?? "") }
    }

    private var pairing: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Wordmark(width: 136)
                        .foregroundStyle(theme.accent)
                    Spacer()
                    themeMenu
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connect to your Mac")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .tracking(-0.8)
                        .accessibilityAddTraits(.isHeader)
                    Text("View your Mac screen or use your iPhone as its mouse and keyboard.")
                        .foregroundStyle(theme.muted)
                }
                VStack(alignment: .leading, spacing: 14) {
                    Label("Screen sharing", systemImage: "display")
                        .font(.system(.headline, design: .rounded))
                        .accessibilityAddTraits(.isHeader)
                    Text("On your Mac, open Archaive → Connections → Open Sharing. Connect both devices to the same Wi-Fi or hotspot.")
                        .font(.subheadline)
                        .foregroundStyle(theme.muted)
                    Button { Task { await openScanner() } } label: {
                        Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PhoneInkButton())
                    Rectangle().fill(theme.line).frame(height: 1).accessibilityHidden(true)
                    TextField("Paste the sharing link", text: $link,
                              prompt: Text("Paste the sharing link").foregroundStyle(theme.muted))
                        .keyboardType(.URL).textContentType(.URL).textInputAutocapitalization(.never)
                        .autocorrectionDisabled().submitLabel(.go)
                        .focused($linkFocused)
                        .onSubmit { connect(link) }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(theme.paper, in: RoundedRectangle(cornerRadius: 12))
                        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(theme.line).allowsHitTesting(false) }
                        .accessibilityLabel("Mac sharing link")
                    Button {
                        connect(link)
                    } label: {
                        Text("Connect").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PhoneInkButton(prominent: false))
                    .disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let error = session.inputError {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(theme.accent)
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                }
                .padding(18)
                .modifier(PhonePanel())
                Label("For mouse and keyboard access, turn on Allow remote control on your Mac before starting the session.",
                      systemImage: "hand.tap")
                    .font(.footnote)
                    .foregroundStyle(theme.muted)
            }
            .frame(maxWidth: 480, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var themeMenu: some View {
        Menu {
            Picker("Theme", selection: $theme) {
                ForEach(AppTheme.allCases) { option in Text(option.name).tag(option) }
            }
        } label: {
            HStack(spacing: 7) {
                ThemeSwatch(theme: theme, selected: false).frame(width: 17, height: 17)
                Text(theme.name).font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(theme.wash.opacity(0.38), in: Capsule())
        }
        .accessibilityLabel("Theme")
        .accessibilityValue(theme.name)
    }

    private var viewer: some View {
        VStack(spacing: 0) {
            if !isFullscreen { viewerToolbar }

            ZStack {
                Color(red: 0.08, green: 0.06, blue: 0.08)
                if phase == .active, let image = session.image {
                    ZoomableScreen(image: image, resetID: resetZoom, controlling: mode == .control, send: session.send)
                } else {
                    Label("Waiting for your Mac", systemImage: "display")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(.white)
                        .padding()
                }
            }
            .clipped()
            .ignoresSafeArea(.container, edges: isFullscreen ? .all : [])

            if !isFullscreen && (verticalSize != .compact || session.controlError != nil || session.image == nil) {
                viewerFooter
            }
        }
        .overlay(alignment: .topTrailing) {
            if isFullscreen {
                Button {
                    isFullscreen = false
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.72), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Exit fullscreen")
                .padding(10)
            }
        }
    }

    private var viewerToolbar: some View {
        HStack(spacing: 8) {
            Button {
                session.disconnect()
                mode = .view
            } label: {
                Image(systemName: "xmark").frame(minWidth: 20)
            }
            .buttonStyle(PhoneInkButton(prominent: false))
            .accessibilityLabel("Disconnect")
            if verticalSize == .compact {
                Wordmark(width: 104).foregroundStyle(theme.accent)
            } else {
                Text("Mac screen")
                    .font(.system(.headline, design: .rounded))
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            if verticalSize == .compact, session.canControl { modePicker.frame(width: 146) }
            if mode == .control && session.canControl { keyboardButton }
            Button {
                resetZoom = UUID()
            } label: {
                Image(systemName: "aspectratio").frame(minWidth: 20)
            }
            .buttonStyle(PhoneInkButton(prominent: false))
            .accessibilityLabel("Fit screen")
            .disabled(session.image == nil)
            Button {
                isFullscreen = true
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right").frame(minWidth: 20)
            }
            .buttonStyle(PhoneInkButton(prominent: false))
            .accessibilityLabel("Enter fullscreen")
            .disabled(session.image == nil)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, verticalSize == .compact ? 3 : 8)
    }

    private var viewerFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            if session.canControl && verticalSize != .compact { modePicker }
            Label(session.controlError ?? viewerStatus,
                  systemImage: session.controlError != nil ? "exclamationmark.circle" : (session.image != nil ? "dot.radiowaves.left.and.right" : "display"))
                .font(.footnote)
                .foregroundStyle(theme.muted)
                .accessibilityIdentifier("stream-status")
                .accessibilityAddTraits(.updatesFrequently)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.white.opacity(0.52))
    }

    private var viewerStatus: String {
        if session.canControl && mode == .control { return "Tap to click, hold to right-click, or swipe with two fingers to scroll." }
        if session.canControl { return "Pinch to zoom or drag to pan. Switch to Control to use your Mac." }
        if session.image != nil, session.address?.controlKey != nil { return "Control is unavailable. Restart sharing on your Mac and scan a new code." }
        return session.status
    }

    private var modePicker: some View {
        Picker("Interaction", selection: $mode) {
            Text("View").tag(ViewerMode.view)
            Text("Control").tag(ViewerMode.control)
        }
        .pickerStyle(.segmented)
    }

    private var keyboardButton: some View {
        Button {
            showKeyboard = true
        } label: {
            Image(systemName: "keyboard").frame(minWidth: 20)
        }
        .buttonStyle(PhoneInkButton(prominent: false))
        .accessibilityLabel("Mac keyboard")
    }

    private func connect(_ value: String) {
        session.connect(value)
        if session.address != nil {
            link = ""
            linkFocused = false
            mode = .view
        }
    }

    @MainActor private func openScanner() async {
        guard DataScannerViewController.isSupported else {
            cameraError = "QR scanning requires a supported iPhone camera. Paste the sharing link instead."
            return
        }
        guard await AVCaptureDevice.requestAccess(for: .video), DataScannerViewController.isAvailable else {
            cameraError = "Allow camera access in Settings to scan your Mac’s QR code, or paste the sharing link instead."
            return
        }
        scanning = true
    }

    private enum ViewerMode { case view, control }

    private struct StreamTask: Equatable {
        let address: ShareAddress?
        let active: Bool
    }
}

private struct PhonePanel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.white.opacity(0.67), in: RoundedRectangle(cornerRadius: 24))
            .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.9)).allowsHitTesting(false) }
    }
}

struct PhoneInkButton: ButtonStyle {
    @Environment(\.appTheme) private var theme
    @Environment(\.isEnabled) private var enabled
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(prominent ? .white : theme.ink)
            .padding(.horizontal, 12)
            .frame(minWidth: 44, minHeight: 44)
            .background(prominent ? theme.accent : theme.wash.opacity(0.38), in: Capsule())
            .opacity(enabled ? (configuration.isPressed ? 0.77 : 1) : 0.48)
    }
}
