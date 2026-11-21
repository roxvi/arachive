import SwiftUI

@MainActor
final class ScreenSession: ObservableObject {
    @Published private(set) var address: ShareAddress?
    @Published private(set) var image: UIImage?
    @Published private(set) var status = "Connecting to your Mac…"
    @Published var inputError: String?
    @Published private(set) var canControl = false
    @Published private(set) var controlError: String?

    private var sequence: UInt64 = 0
    private var epoch: UInt64 = 0
    private var pending: [PhoneControl.Command] = []
    private var sender: Task<Void, Never>?

    private let transport: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 5
        return URLSession(configuration: config, delegate: LocalOnlyRedirects(), delegateQueue: nil)
    }()

    func connect(_ text: String) {
        guard let parsed = ShareAddress(text) else {
            inputError = "Use the full sharing link from your Mac’s Archaive menu. Connect both devices to the same Wi-Fi or phone hotspot."
            return
        }
        resetControls()
        sequence = 0
        epoch = 0
        inputError = nil
        image = nil
        status = "Connecting to your Mac…"
        address = parsed
    }

    func disconnect() {
        resetControls()
        address = nil
        image = nil
        inputError = nil
    }

    func pause() {
        resetControls()
        image = nil
        status = "Sharing paused while the app is in the background."
    }

    func receiveFrames(from address: ShareAddress) async {
        status = "Connecting to your Mac…"
        while !Task.isCancelled {
            do {
                let (data, response) = try await transport.data(from: address.frameURL)
                try Task.checkCancellation()
                guard self.address == address else { return }
                if (response as? HTTPURLResponse)?.statusCode == 404 {
                    resetControls()
                    image = nil
                    status = "This session has ended. Disconnect and scan a new QR code on your Mac."
                    return
                }
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      response.mimeType == "image/jpeg", data.count <= 6_000_000,
                      let frame = UIImage(data: data) else { throw FrameError.unavailable }
                if let key = address.controlKey,
                   let current = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: PhoneControl.sequenceHeader),
                   let serverSequence = UInt64(current),
                   let freshness = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: PhoneControl.epochHeader),
                   let serverEpoch = UInt64(freshness), serverEpoch >= epoch,
                   let proof = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: PhoneControl.proofHeader),
                   PhoneControl.verifyFrame(data, proof: proof, sequence: serverSequence, epoch: serverEpoch, key: key) {
                    epoch = serverEpoch
                    sequence = max(sequence, serverSequence)
                    if !canControl { canControl = true }
                } else if canControl {
                    resetControls()
                }
                image = frame
                if status != "Mac screen is live" { status = "Mac screen is live" }
                try await Task.sleep(for: .milliseconds(125))
            } catch {
                guard !Task.isCancelled, self.address == address else { return }
                resetControls()
                image = nil
                status = "Screen unavailable. Check sharing on your Mac, Wi-Fi, and Local Network access in Settings. Retrying…"
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }

    func send(_ command: PhoneControl.Command) {
        guard let address, let key = address.controlKey, canControl, image != nil, command.isValid else { return }
        // Motion can arrive faster than the network. Keep the latest drag position and
        // make room for button releases before adding any more motion.
        if case .dragMove = command, case .dragMove? = pending.last {
            pending[pending.count - 1] = command
        } else if case .scroll(_, let x, let y) = command,
                  case .scroll(let point, let previousX, let previousY)? = pending.last {
            pending[pending.count - 1] = .scroll(point, horizontal: max(-240, min(240, x + previousX)),
                                                      vertical: max(-240, min(240, y + previousY)))
        } else {
            if pending.count >= 12 {
                guard !command.isMotion, let motion = pending.firstIndex(where: \.isMotion) else { return }
                pending.remove(at: motion)
            }
            pending.append(command)
        }

        guard sender == nil else { return }
        sender = Task {
            defer { if !Task.isCancelled { sender = nil } }
            while !pending.isEmpty && !Task.isCancelled {
                let next = pending.removeFirst()
                do {
                    guard sequence < UInt64.max else { throw FrameError.unavailable }
                    sequence += 1
                    let packet = try PhoneControl.seal(next, sequence: sequence, epoch: epoch, key: key)
                    var request = URLRequest(url: address.controlURL, timeoutInterval: 2)
                    request.httpMethod = "POST"
                    request.httpBody = packet
                    request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                    let (_, response) = try await transport.data(for: request)
                    try Task.checkCancellation()
                    switch (response as? HTTPURLResponse)?.statusCode {
                    case 204:
                        if controlError != nil { controlError = nil }
                    case 409:
                        controlError = "Input was interrupted. Try again or check Accessibility on your Mac."
                    default:
                        controlError = "The Mac rejected this input. Try again or scan a fresh control QR code."
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    pending.removeAll()
                    controlError = "Input didn’t reach your Mac. Check your connection and try again."
                    return
                }
            }
        }
    }

    private func resetControls() {
        sender?.cancel()
        sender = nil
        pending.removeAll()
        if canControl { canControl = false }
        if controlError != nil { controlError = nil }
    }

    private enum FrameError: Error { case unavailable }
}

// A scanned LAN endpoint must never redirect this viewer to another destination.
private final class LocalOnlyRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
