import Foundation

/// A known host presenting a key we have not pinned (a changed key, or a key of
/// a different algorithm than the one already trusted). Surfaced to the UI so the
/// user — not the app — decides whether to trust it.
struct PendingHostKeyMismatch: Sendable, Identifiable, Equatable {
    let hostname: String
    let port: UInt16
    let keyType: String
    let publicKeyData: Data
    let existingFingerprint: String
    let newFingerprint: String

    var id: String { "\(hostname):\(port):\(keyType)" }
}

enum HostKeyVerificationError: Error, Equatable {
    case mismatch(existingFingerprint: String, newFingerprint: String)
}

actor HostKeyVerifier {
    private let store: KnownHostsStore
    private var pendingMismatch: PendingHostKeyMismatch?

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
        let storedForHost = await store.lookupAll(hostname: hostname, port: port)

        // First time we have ever seen this host: trust on first use (TOFU).
        guard !storedForHost.isEmpty else {
            let entry = SSHHostKey(
                hostname: hostname,
                port: port,
                keyType: keyType,
                publicKeyData: publicKeyData,
                fingerprint: fingerprint,
                firstSeenDate: Date()
            )
            try await store.trust(hostKey: entry)
            return
        }

        // Host is already known. Accept only if the presented key matches one we
        // have already pinned — checked across ALL key types, so an attacker
        // cannot bypass pinning by presenting a different host-key algorithm than
        // the one originally trusted.
        let isKnownKey = storedForHost.contains { stored in
            stored.publicKeyData == publicKeyData
                || (stored.publicKeyData.isEmpty && stored.fingerprint == fingerprint)
        }
        if isKnownKey { return }

        // Known host, unrecognised key (changed key, or a new key type). Record
        // the pending decision for the UI and block the connection.
        let existing = storedForHost.first { $0.keyType == keyType } ?? storedForHost[0]
        pendingMismatch = PendingHostKeyMismatch(
            hostname: hostname,
            port: port,
            keyType: keyType,
            publicKeyData: publicKeyData,
            existingFingerprint: existing.fingerprint,
            newFingerprint: fingerprint
        )
        throw HostKeyVerificationError.mismatch(
            existingFingerprint: existing.fingerprint,
            newFingerprint: fingerprint
        )
    }

    /// Returns and clears the last recorded mismatch (set when `verify` blocked a
    /// known host that presented an unrecognised key).
    func takePendingMismatch() -> PendingHostKeyMismatch? {
        let pending = pendingMismatch
        pendingMismatch = nil
        return pending
    }

    /// Pin a key the user explicitly approved after a mismatch warning. A new key
    /// type is added alongside the existing one(s); a changed key of the same type
    /// replaces the previous entry.
    func trust(_ pending: PendingHostKeyMismatch) async {
        let entry = SSHHostKey(
            hostname: pending.hostname,
            port: pending.port,
            keyType: pending.keyType,
            publicKeyData: pending.publicKeyData,
            fingerprint: pending.newFingerprint,
            firstSeenDate: Date()
        )
        try? await store.trust(hostKey: entry)
    }
}
