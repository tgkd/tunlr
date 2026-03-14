import Foundation

struct SSHHostKey: Codable, Sendable, Identifiable, Equatable {
    var id: String { "\(hostname):\(port):\(keyType)" }
    let hostname: String
    let port: UInt16
    let keyType: String
    let publicKeyData: Data
    let fingerprint: String
    let firstSeenDate: Date
}
