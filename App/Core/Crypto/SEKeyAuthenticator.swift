import Foundation
import CryptoKit

struct SEKeyAuthenticator: SSHAuthenticatable {
    let keyTag: String
    let manager: SecureEnclaveKeyManager

    func authenticate(sessionHash: Data) async throws -> Data {
        let privateKey = try await manager.loadKey(tag: keyTag)
        let signature = try privateKey.signature(for: sessionHash)
        let p1363 = signature.rawRepresentation
        let der = SecureEnclaveKeyManager.p1363ToDER(signature: p1363)
        return SecureEnclaveKeyManager.encodeSSHSignatureBlob(derSignature: der)
    }
}
