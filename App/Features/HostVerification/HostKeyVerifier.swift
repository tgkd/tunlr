import Foundation

struct HostKeyVerificationRequest: Sendable, Identifiable {
    let hostname: String
    let port: UInt16
    let keyType: String
    let fingerprint: String

    var id: String { "\(hostname):\(port):\(keyType)" }
}

enum HostKeyVerificationResult: Sendable {
    case trusted
    case needsUserApproval(HostKeyVerificationRequest)
    case mismatch(existingFingerprint: String, newFingerprint: String)
}

enum HostKeyVerificationError: Error, Equatable {
    case mismatch(existingFingerprint: String, newFingerprint: String)
}

actor HostKeyVerifier {
    private let store: KnownHostsStore

    init(store: KnownHostsStore) {
        self.store = store
    }

    func verify(
        hostname: String,
        port: UInt16,
        keyType: String,
        publicKeyData: Data
    ) async throws {
        let fingerprint = FingerprintFormatter.sha256Fingerprint(of: publicKeyData)
        let stored = await store.lookup(hostname: hostname, port: port, keyType: keyType)

        if let stored {
            if stored.publicKeyData == publicKeyData
                || (stored.publicKeyData.isEmpty && stored.fingerprint == fingerprint) {
                return
            } else {
                throw HostKeyVerificationError.mismatch(
                    existingFingerprint: stored.fingerprint,
                    newFingerprint: fingerprint
                )
            }
        }

        let hostKeyEntry = SSHHostKey(
            hostname: hostname,
            port: port,
            keyType: keyType,
            publicKeyData: publicKeyData,
            fingerprint: fingerprint,
            firstSeenDate: Date()
        )
        try await store.trust(hostKey: hostKeyEntry)
    }

    func check(
        hostname: String,
        port: UInt16,
        keyType: String,
        publicKeyData: Data
    ) async -> HostKeyVerificationResult {
        let fingerprint = FingerprintFormatter.sha256Fingerprint(of: publicKeyData)
        let stored = await store.lookup(hostname: hostname, port: port, keyType: keyType)

        if let stored {
            if stored.publicKeyData == publicKeyData
                || (stored.publicKeyData.isEmpty && stored.fingerprint == fingerprint) {
                return .trusted
            } else {
                return .mismatch(
                    existingFingerprint: stored.fingerprint,
                    newFingerprint: fingerprint
                )
            }
        }

        return .needsUserApproval(HostKeyVerificationRequest(
            hostname: hostname,
            port: port,
            keyType: keyType,
            fingerprint: fingerprint
        ))
    }
}
