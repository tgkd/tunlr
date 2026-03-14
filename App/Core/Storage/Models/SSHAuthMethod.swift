import Foundation

enum SSHAuthMethod: Codable, Sendable, Equatable {
    case secureEnclaveKey(keyTag: String)
    case importedKey(keyID: UUID)
    case password
}
