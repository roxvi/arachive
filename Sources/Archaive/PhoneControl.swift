import CryptoKit
import Foundation

enum PhoneControl {
    static let proofHeader = "X-Archaive-Control-Proof"
    static let epochHeader = "X-Archaive-Control-Epoch"
    static let sequenceHeader = "X-Archaive-Control-Sequence"
    static let maximumPacketSize = 4096
    static let maximumTextLength = 256

    struct Point: Codable, Equatable {
        let x: Double
        let y: Double

        var isValid: Bool { (0...1).contains(x) && (0...1).contains(y) }
    }

    enum Key: String, Codable, CaseIterable {
        case escape, tab, delete, enter, left, right, up, down, undo, copy, paste, selectAll
    }

    enum Command: Codable, Equatable {
        case click(Point), doubleClick(Point), rightClick(Point)
        case dragStart(Point), dragMove(Point), dragEnd(Point)
        case scroll(Point, horizontal: Int32, vertical: Int32)
        case type(String), key(Key)

        var isValid: Bool {
            switch self {
            case .click(let point), .doubleClick(let point), .rightClick(let point),
                 .dragStart(let point), .dragMove(let point), .dragEnd(let point):
                return point.isValid
            case .scroll(let point, let horizontal, let vertical):
                return point.isValid && (-240...240).contains(horizontal) && (-240...240).contains(vertical)
            case .type(let text):
                return !text.isEmpty && text.utf16.count <= PhoneControl.maximumTextLength
            case .key:
                return true
            }
        }

        var isMotion: Bool {
            switch self {
            case .dragMove, .scroll: true
            default: false
            }
        }
    }

    struct PairingKey: Equatable {
        private let bytes: Data

        init() { bytes = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) } }

        init?(_ code: String) {
            guard code.utf8.count == 43,
                  let bytes = Data(base64Encoded: code.replacingOccurrences(of: "-", with: "+")
                      .replacingOccurrences(of: "_", with: "/") + "="), bytes.count == 32 else { return nil }
            self.bytes = bytes
            guard self.code == code else { return nil }
        }

        var code: String {
            bytes.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }

        fileprivate var symmetricKey: SymmetricKey { SymmetricKey(data: bytes) }
    }

    static var currentEpoch: UInt64 { UInt64(ProcessInfo.processInfo.systemUptime / 5) }

    private struct Packet: Codable {
        let sequence: UInt64
        let epoch: UInt64
        let command: Command
    }

    static func seal(_ command: Command, sequence: UInt64, epoch: UInt64, key: PairingKey) throws -> Data {
        let data = try JSONEncoder().encode(Packet(sequence: sequence, epoch: epoch, command: command))
        return try ChaChaPoly.seal(data, using: key.symmetricKey).combined
    }

    private static func frameMessage(_ frame: Data, sequence: UInt64, epoch: UInt64) -> Data {
        // A fixed-width prefix keeps this signature separate from the encrypted input messages.
        var header = Data("Archaive frame".utf8)
        withUnsafeBytes(of: sequence.bigEndian) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: epoch.bigEndian) { header.append(contentsOf: $0) }
        return header + frame
    }

    static func verifyFrame(_ frame: Data, proof: String, sequence: UInt64, epoch: UInt64, key: PairingKey) -> Bool {
        guard let code = Data(base64Encoded: proof) else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(code, authenticating: frameMessage(frame, sequence: sequence, epoch: epoch),
                                                      using: key.symmetricKey)
    }

    struct Receiver {
        private let key: PairingKey
        private(set) var sequence: UInt64 = 0

        init(key: PairingKey) { self.key = key }

        func headers(for frame: Data, epoch: UInt64) -> String {
            let proof = Data(HMAC<SHA256>.authenticationCode(for: frameMessage(frame, sequence: sequence, epoch: epoch),
                                                            using: key.symmetricKey)).base64EncodedString()
            return "\(sequenceHeader): \(sequence)\r\n\(epochHeader): \(epoch)\r\n\(proofHeader): \(proof)\r\n"
        }

        mutating func accept(_ data: Data, epoch: UInt64) -> Command? {
            guard data.count <= maximumPacketSize,
                  let sealed = try? ChaChaPoly.SealedBox(combined: data),
                  let plain = try? ChaChaPoly.open(sealed, using: key.symmetricKey),
                  let packet = try? JSONDecoder().decode(Packet.self, from: plain),
                  packet.epoch <= epoch, epoch - packet.epoch <= 1,
                  packet.sequence > sequence, packet.command.isValid else { return nil }
            sequence = packet.sequence
            return packet.command
        }
    }
}
