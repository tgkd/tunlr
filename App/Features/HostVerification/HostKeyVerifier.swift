import Foundation

struct HostKeyVerificationRequest: Sendable {
    let hostname: String
    let port: UInt16
    let keyType: String
    let fingerprint: String
}

enum HostKeyVerificationResult: Sendable {
    case trusted
    case needsUserApproval(HostKeyVerificationRequest)
    case mismatch(existingFingerprint: String, newFingerprint: String)
}

enum HostKeyVerificationError: Error, Equatable {
    case mismatch(existingFingerprint: String, newFingerprint: String)
    case rejected
}

actor HostKeyVerifier {
    private let store: KnownHostsStore
    private let approvalHandler: @Sendable (HostKeyVerificationRequest) async -> Bool

    init(
        store: KnownHostsStore,
        approvalHandler: @escaping @Sendable (HostKeyVerificationRequest) async -> Bool
    ) {
        self.store = store
        self.approvalHandler = approvalHandler
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
            if stored.publicKeyData == publicKeyData {
                return
            } else {
                throw HostKeyVerificationError.mismatch(
                    existingFingerprint: stored.fingerprint,
                    newFingerprint: fingerprint
                )
            }
        }

        let request = HostKeyVerificationRequest(
            hostname: hostname,
            port: port,
            keyType: keyType,
            fingerprint: fingerprint
        )
        let approved = await approvalHandler(request)

        if approved {
            let hostKeyEntry = SSHHostKey(
                hostname: hostname,
                port: port,
                keyType: keyType,
                publicKeyData: publicKeyData,
                fingerprint: fingerprint,
                firstSeenDate: Date()
            )
            try await store.trust(hostKey: hostKeyEntry)
        } else {
            throw HostKeyVerificationError.rejected
        }
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
            if stored.publicKeyData == publicKeyData {
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
