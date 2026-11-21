import Foundation

struct ShareAddress: Equatable {
    let frameURL: URL
    let controlURL: URL
    let controlKey: PhoneControl.PairingKey?

    init?(_ text: String) {
        guard var parts = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = parts.host,
              Self.isLocalIPv4(host), let port = parts.port, (1...65535).contains(port),
              parts.user == nil, parts.password == nil, parts.query == nil else { return nil }
        switch parts.scheme {
        case "http":
            guard parts.fragment == nil else { return nil }
            controlKey = nil
        case "archaive-control":
            guard let code = parts.percentEncodedFragment, let key = PhoneControl.PairingKey(code) else { return nil }
            controlKey = key
            parts.scheme = "http"
            parts.fragment = nil
        default:
            return nil
        }
        let path = parts.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
        guard path.count == 3, path[0].isEmpty, path[2].isEmpty,
              path[1].count == 32, path[1].utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
              let base = parts.url else { return nil }
        frameURL = base.appendingPathComponent("frame")
        controlURL = base.appendingPathComponent("control")
    }

    private static func isLocalIPv4(_ host: String) -> Bool {
        let pieces = host.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 4 else { return false }
        let octets = pieces.compactMap { piece -> UInt8? in
            guard !piece.isEmpty, piece.utf8.allSatisfy({ (48...57).contains($0) }),
                  piece.count == 1 || piece.first != "0" else { return nil }
            return UInt8(piece)
        }
        guard octets.count == 4 else { return false }
        return octets[0] == 10 || (octets[0] == 172 && (16...31).contains(octets[1])) ||
            (octets[0] == 192 && octets[1] == 168) || (octets[0] == 169 && octets[1] == 254)
    }
}
