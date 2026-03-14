import Foundation

protocol SSHAuthenticatable: Sendable {
    func authenticate(sessionHash: Data) async throws -> Data
}
