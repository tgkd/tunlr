import Foundation
import CryptoKit

struct FingerprintFormatter: Sendable {
    static func sha256Fingerprint(of publicKeyData: Data) -> String {
        let hash = SHA256.hash(data: publicKeyData)
        let base64 = Data(hash).base64EncodedString()
        let trimmed = base64.replacingOccurrences(of: "=", with: "")
        return "SHA256:\(trimmed)"
    }

    static func hexFingerprint(of publicKeyData: Data) -> String {
        let hash = SHA256.hash(data: publicKeyData)
        return hash.map { String(format: "%02x", $0) }.joined(separator: ":")
    }
}
