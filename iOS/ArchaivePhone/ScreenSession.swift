import SwiftUI

@MainActor
final class ScreenSession: ObservableObject {
    @Published private(set) var address: ShareAddress?
    @Published private(set) var image: UIImage?
    @Published private(set) var status = "Connecting to your Mac…"
    @Published var inputError: String?

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
        inputError = nil
        image = nil
        status = "Connecting to your Mac…"
        address = parsed
    }

    func disconnect() {
        address = nil
        image = nil
        inputError = nil
    }

    func pause() {
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
                    image = nil
                    status = "This session has ended. Disconnect and scan a new QR code on your Mac."
                    return
                }
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      response.mimeType == "image/jpeg", data.count <= 6_000_000,
                      let frame = UIImage(data: data) else { throw FrameError.unavailable }
                image = frame
                status = "Live · Mac screen"
                try await Task.sleep(for: .milliseconds(125))
            } catch {
                guard !Task.isCancelled, self.address == address else { return }
                image = nil
                status = "Screen unavailable. Check sharing on your Mac, Wi-Fi, and Local Network access in Settings. Retrying…"
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
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
