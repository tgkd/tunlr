import Foundation

enum KeyStorageType: String, Codable, Sendable {
    case secureEnclave
    case keychain
}

struct SSHIdentity: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    let label: String
    let keyType: String
    let publicKeyData: Data
    let createdAt: Date
    let storageType: KeyStorageType
}
