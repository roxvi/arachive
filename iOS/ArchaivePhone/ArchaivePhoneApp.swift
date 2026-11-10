import SwiftUI
import VisionKit
import AVFoundation

@main
struct ArchaivePhoneApp: App {
    var body: some Scene { WindowGroup { PhoneView() } }
}

struct PhoneView: View {
    @StateObject private var session = ScreenSession()
    @Environment(\.scenePhase) private var phase
    @State private var link = ""
    @State private var scanning = false
    @State private var cameraError: String?
    @State private var resetZoom = UUID()

    var body: some View {
        NavigationStack {
            Group {
                if session.address != nil { viewer }
                else { pairing }
            }
            .navigationTitle("Archaive")
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(Color("AccentColor"))
        .task(id: StreamTask(address: session.address, active: phase == .active)) {
            if phase == .active, let address = session.address {
                await session.receiveFrames(from: address)
            } else { session.pause() }
        }
        .onChange(of: phase) { _, next in
            if next != .active {
                session.pause()
                scanning = false
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
        .onChange(of: session.image != nil) { _, live in
            UIApplication.shared.isIdleTimerDisabled = live && phase == .active
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .sheet(isPresented: $scanning) {
            NavigationStack {
                QRScanner(scanned: { value in
                    scanning = false
                    session.connect(value)
                    if session.address != nil { link = "" }
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
        .alert("Camera unavailable", isPresented: Binding(get: { cameraError != nil }, set: { if !$0 { cameraError = nil } })) {
            Button("OK") { cameraError = nil }
        } message: { Text(cameraError ?? "") }
    }

    private var pairing: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Text("A").font(.system(size: 34, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(Color(red: 0.02, green: 0.59, blue: 0.41), in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityHidden(true)
                    Text("Your Mac, on your iPhone").font(.title2.bold())
                    Text("Keep your desktop in view while your Mac’s screen is dimmed.")
                        .foregroundStyle(.secondary)
                }.padding(.vertical, 8)
            }
            Section("Connect to your Mac") {
                Text("On your Mac, open Archaive → Share Screen to Phone… → Start Sharing. Keep both devices on the same Wi-Fi or phone hotspot.")
                Button { Task { await openScanner() } } label: {
                    Label("Scan QR Code", systemImage: "qrcode.viewfinder").frame(minHeight: 36)
                }
                TextField("Paste the sharing link", text: $link)
                    .keyboardType(.URL).textContentType(.URL).textInputAutocapitalization(.never)
                    .autocorrectionDisabled().submitLabel(.go)
                    .onSubmit { connect() }
                    .accessibilityLabel("Mac sharing link")
                Button("Connect", action: connect).disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let error = session.inputError {
                    Text(error).foregroundStyle(.red).accessibilityAddTraits(.updatesFrequently)
                }
            }
            Section {
                Text("View only. Mac dimming won’t darken this view; adjust your iPhone’s brightness normally. Pinch to zoom once connected.")
                Text("Use a trusted network. The local stream is unencrypted and anyone holding its session link can view it. Stop sharing from your Mac’s menu.")
            }.foregroundStyle(.secondary)
        }
    }

    private var viewer: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                if phase == .active, let image = session.image {
                    ZoomableScreen(image: image, resetID: resetZoom)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "display").font(.largeTitle)
                        Text("Waiting for your Mac").font(.headline)
                    }.foregroundStyle(.white).padding()
                }
            }
            Text(session.status).font(.footnote).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding()
                .accessibilityIdentifier("stream-status")
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("Disconnect") { session.disconnect() } }
            ToolbarItem(placement: .topBarTrailing) { Button("Fit") { resetZoom = UUID() }.disabled(session.image == nil) }
        }
    }

    private func connect() {
        session.connect(link)
        if session.address != nil { link = "" }
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

    private struct StreamTask: Equatable {
        let address: ShareAddress?
        let active: Bool
    }
}
