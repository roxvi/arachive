import AppKit
import ScreenCaptureKit
import CoreImage
import Network

// Capture the compositor, never the panel backlight. Control/UI state is main-queue only;
// capture buffers and network state are confined to queue. Framework callbacks cross
// those queues explicitly, so this class provides its own Sendable synchronization.
final class PhoneShare: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "Archaive.PhoneShare")
    private let context = CIContext()
    private var stream: SCStream?
    private var listener: NWListener?
    private var clients: [UUID: NWConnection] = [:]
    private var capturing: ObjectIdentifier?
    private var networkSession: UUID?
    private var frame: Data?
    private var frameTime = Date.distantPast
    private var session: UUID?
    private(set) var active = false
    private(set) var starting = false
    private(set) var links: [String] = []
    var changed: (() -> Void)?
    var failed: ((String) -> Void)?

    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !active, !starting else { return }
        starting = true
        let id = UUID()
        session = id
        changed?()
        Task { @MainActor in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard session == id else { return }
                guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first else {
                    throw ShareError.noDisplay
                }
                let config = SCStreamConfiguration()
                let scale = min(1, 1280.0 / Double(display.width))
                config.width = max(2, Int(Double(display.width) * scale) / 2 * 2)
                config.height = max(2, Int(Double(display.height) * scale) / 2 * 2)
                config.minimumFrameInterval = CMTime(value: 1, timescale: 10)
                config.queueDepth = 3
                config.pixelFormat = kCVPixelFormatType_32BGRA
                config.showsCursor = true
                let capture = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: config, delegate: self)
                try capture.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
                stream = capture
                let captureID = ObjectIdentifier(capture)
                queue.async { self.capturing = captureID }
                try await capture.startCapture()
                guard session == id else { try? await capture.stopCapture(); return }
                let server = try NWListener(using: .tcp, on: .any)
                let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
                listener = server
                queue.async { self.networkSession = id }
                server.newConnectionHandler = { [weak self] connection in
                    guard let self, self.networkSession == id else { connection.cancel(); return }
                    self.accept(connection, token: token)
                }
                server.stateUpdateHandler = { [weak self, weak server] state in
                    DispatchQueue.main.async {
                        guard let self, let server, self.session == id else { return }
                        switch state {
                        case .ready:
                            guard let port = server.port else { return }
                            self.links = Self.addresses().map { "http://\($0):\(port.rawValue)/\(token)/" }
                            self.starting = false
                            self.active = true
                            self.changed?()
                        case .failed(let error): self.fail(error.localizedDescription)
                        default: break
                        }
                    }
                }
                server.start(queue: queue)
            } catch {
                guard session == id else { return }
                fail("Allow Screen Recording in System Settings → Privacy & Security, then retry. \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        session = nil
        let capture = stream
        stream = nil
        listener?.cancel()
        listener = nil
        queue.async { [self] in
            capturing = nil
            networkSession = nil
            for connection in clients.values { connection.cancel() }
            clients.removeAll()
            frame = nil
            frameTime = .distantPast
        }
        if let capture { Task { try? await capture.stopCapture() } }
        starting = false
        active = false
        links = []
        changed?()
    }

    private func fail(_ message: String) {
        stop()
        failed?(message)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream === stream else { return }
            self.fail("Screen sharing stopped. \(error.localizedDescription)")
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard capturing == ObjectIdentifier(stream), type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int,
              let state = SCFrameStatus(rawValue: status) else { return }
        if state == .idle {
            // Static desktops produce idle frames; the last complete image is still current.
            if frame != nil { frameTime = Date() }
            return
        }
        guard state == .complete, let buffer = sampleBuffer.imageBuffer else {
            frame = nil
            return
        }
        // No brightness multiplier: lowering hardware brightness must never darken this image.
        frame = context.jpegRepresentation(of: CIImage(cvPixelBuffer: buffer), colorSpace: CGColorSpaceCreateDeviceRGB(), options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.7])
        frameTime = Date()
    }

    private func accept(_ connection: NWConnection, token: String) {
        guard clients.count < 8 else { connection.cancel(); return }
        let id = UUID()
        clients[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            if case .cancelled = state { self?.clients.removeValue(forKey: id) }
            if case .failed = state { self?.clients.removeValue(forKey: id) }
        }
        connection.start(queue: queue)
        // Bound both slow requests and slow receivers. No unbounded frame backlog.
        queue.asyncAfter(deadline: .now() + 5) { [weak connection] in connection?.cancel() }
        receive(connection, token: token, data: Data())
    }

    private func receive(_ connection: NWConnection, token: String, data: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] bytes, _, done, error in
            guard let self else { connection.cancel(); return }
            var request = data
            request.append(bytes ?? Data())
            guard request.count <= 8192, error == nil else { connection.cancel(); return }
            if request.range(of: Data("\r\n\r\n".utf8)) != nil {
                let route = PhoneShareHTTP.route(request, token: token)
                switch route {
                case .page: self.respond(connection, status: "200 OK", type: "text/html; charset=utf-8", body: Data(PhoneShareHTTP.page.utf8))
                case .frame:
                    if let frame = self.frame, Date().timeIntervalSince(self.frameTime) < 5 {
                        self.respond(connection, status: "200 OK", type: "image/jpeg", body: frame)
                    } else { self.respond(connection, status: "503 Service Unavailable", type: "text/plain", body: Data("Waiting for screen capture".utf8)) }
                case .missing: self.respond(connection, status: "404 Not Found", type: "text/plain", body: Data("Sharing link expired or incorrect".utf8))
                }
            } else if done { connection.cancel() }
            else { self.receive(connection, token: token, data: request) }
        }
    }

    private func respond(_ connection: NWConnection, status: String, type: String, body: Data) {
        let headers = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nX-Content-Type-Options: nosniff\r\nContent-Security-Policy: default-src 'none'; img-src 'self' blob:; connect-src 'self'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; frame-ancestors 'none'\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(headers.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }

    private static func addresses() -> [String] {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0 else { return [] }
        defer { freeifaddrs(interfaces) }
        var results: [String] = []
        var cursor = interfaces
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let flags = Int32(entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let value = String(cString: host)
                if String(cString: entry.pointee.ifa_name) == "en0" { results.insert(value, at: 0) }
                else { results.append(value) }
            }
        }
        return results.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    private enum ShareError: LocalizedError {
        case noDisplay
        var errorDescription: String? { "No display is available to share." }
    }
}
