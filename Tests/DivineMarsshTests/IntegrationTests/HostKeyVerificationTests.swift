import Testing
import Foundation
import CryptoKit
@testable import DivineMarssh

// MARK: - Integration: Host Key Verification Flow

struct HostKeyVerificationIntegrationTests {

    private func makeTestPublicKeyData(keyType: String = "ssh-ed25519", seed: UInt8 = 0xAA) -> Data {
        var data = Data()
        var len = UInt32(keyType.utf8.count).bigEndian
        data.append(Data(bytes: &len, count: 4))
        data.append(Data(keyType.utf8))
        data.append(Data(repeating: seed, count: 32))
        return data
    }

    private func makeStore() throws -> KnownHostsStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return try KnownHostsStore(directory: dir)
    }

    // MARK: - First Connect Auto-Trusts (TOFU)

    @Test func firstConnectionSilentlyStoresKey() async throws {
        let store = try makeStore()
        let verifier = HostKeyVerifier(store: store)

        let pubKeyData = makeTestPublicKeyData()
        try await verifier.verify(
            hostname: "newhost.example.com",
            port: 22,
            keyType: "ssh-ed25519",
            publicKeyData: pubKeyData
        )

        let stored = try await store.lookup(hostname: "newhost.example.com", port: 22, keyType: "ssh-ed25519")
        #expect(stored != nil)
        #expect(stored?.publicKeyData == pubKeyData)
        #expect(stored?.fingerprint == FingerprintFormatter.sha256Fingerprint(of: pubKeyData))
    }

    // MARK: - Second Connect Matches

    @Test func secondConnectionWithSameKeySilentlySucceeds() async throws {
        let store = try makeStore()
        let verifier = HostKeyVerifier(store: store)

        let pubKeyData = makeTestPublicKeyData()

        try await verifier.verify(
            hostname: "known.example.com",
            port: 22,
            keyType: "ssh-ed25519",
            publicKeyData: pubKeyData
        )

        try await verifier.verify(
            hostname: "known.example.com",
            port: 22,
            keyType: "ssh-ed25519",
            publicKeyData: pubKeyData
        )

        let stored = try await store.lookup(hostname: "known.example.com", port: 22, keyType: "ssh-ed25519")
        #expect(stored?.publicKeyData == pubKeyData)
    }

    // MARK: - Changed Key Blocks

    @Test func changedKeyTriggersHardBlock() async throws {
        let store = try makeStore()
        let verifier = HostKeyVerifier(store: store)

        let originalKey = makeTestPublicKeyData(seed: 0xAA)
        try await verifier.verify(
            hostname: "changinghost.example.com",
            port: 22,
            keyType: "ssh-ed25519",
            publicKeyData: originalKey
        )

        let changedKey = makeTestPublicKeyData(seed: 0xBB)

        do {
            try await verifier.verify(
                hostname: "changinghost.example.com",
                port: 22,
                keyType: "ssh-ed25519",
                publicKeyData: changedKey
            )
            Issue.record("Expected mismatch error")
        } catch let error as HostKeyVerificationError {
            if case .mismatch(let existing, let new) = error {
                #expect(existing.hasPrefix("SHA256:"))
                #expect(new.hasPrefix("SHA256:"))
                #expect(existing != new)
            } else {
                Issue.record("Expected mismatch error, got: \(error)")
            }
        }
    }

    @Test func changedKeyDoesNotOverwriteOriginal() async throws {
        let store = try makeStore()
        let verifier = HostKeyVerifier(store: store)

        let originalKey = makeTestPublicKeyData(seed: 0xCC)
        try await verifier.verify(
            hostname: "preserved.example.com",
            port: 22,
            keyType: "ssh-ed25519",
            publicKeyData: originalKey
        )

        let changedKey = makeTestPublicKeyData(seed: 0xDD)
        try? await verifier.verify(
            hostname: "preserved.example.com",
            port: 22,
            keyType: "ssh-ed25519",
            publicKeyData: changedKey
        )

        let stored = try await store.lookup(hostname: "preserved.example.com", port: 22, keyType: "ssh-ed25519")
        #expect(stored?.publicKeyData == originalKey)
    }

    // MARK: - Cross-Type Pinning (MITM bypass closed)

    @Test func differentKeyTypeOnKnownHostIsBlocked() async throws {
        let store = try makeStore()
        let verifier = HostKeyVerifier(store: store)

        let edKey = makeTestPublicKeyData(keyType: "ssh-ed25519", seed: 0xA1)
        try await verifier.verify(
            hostname: "pinned.example.com", port: 22,
            keyType: "ssh-ed25519", publicKeyData: edKey
        )

        // Attacker presents a different host-key algorithm for the same host.
        let ecdsaKey = makeTestPublicKeyData(keyType: "ecdsa-sha2-nistp256", seed: 0xB2)
        await #expect(throws: HostKeyVerificationError.self) {
            try await verifier.verify(
                hostname: "pinned.example.com", port: 22,
                keyType: "ecdsa-sha2-nistp256", publicKeyData: ecdsaKey
            )
        }

        // The new type must NOT have been auto-stored.
        let storedEcdsa = try await store.lookup(
            hostname: "pinned.example.com", port: 22, keyType: "ecdsa-sha2-nistp256"
        )
        #expect(storedEcdsa == nil)

        // The verifier exposes the pending decision for the UI.
        let pending = await verifier.takePendingMismatch(hostname: "pinned.example.com", port: 22)
        #expect(pending?.hostname == "pinned.example.com")
        #expect(pending?.keyType == "ecdsa-sha2-nistp256")
        // Taking it clears it.
        let cleared = await verifier.takePendingMismatch(hostname: "pinned.example.com", port: 22)
        #expect(cleared == nil)
    }

    @Test func trustingPendingKeyPinsItAlongsideExisting() async throws {
        let store = try makeStore()
        let verifier = HostKeyVerifier(store: store)

        let edKey = makeTestPublicKeyData(keyType: "ssh-ed25519", seed: 0xC3)
        try await verifier.verify(
            hostname: "multi.example.com", port: 22,
            keyType: "ssh-ed25519", publicKeyData: edKey
        )

        let ecdsaKey = makeTestPublicKeyData(keyType: "ecdsa-sha2-nistp256", seed: 0xD4)
        _ = try? await verifier.verify(
            hostname: "multi.example.com", port: 22,
            keyType: "ecdsa-sha2-nistp256", publicKeyData: ecdsaKey
        )
        let pending = await verifier.takePendingMismatch(hostname: "multi.example.com", port: 22)
        #expect(pending != nil)

        try await verifier.trust(pending!)

        // Both key types are now pinned and verify cleanly.
        try await verifier.verify(
            hostname: "multi.example.com", port: 22,
            keyType: "ssh-ed25519", publicKeyData: edKey
        )
        try await verifier.verify(
            hostname: "multi.example.com", port: 22,
            keyType: "ecdsa-sha2-nistp256", publicKeyData: ecdsaKey
        )
        let all = try await store.lookupAll(hostname: "multi.example.com", port: 22)
        #expect(all.count == 2)
    }

    // MARK: - Multi-host Verification

    @Test func differentHostsAreIndependent() async throws {
        let store = try makeStore()
        let verifier = HostKeyVerifier(store: store)

        let key1 = makeTestPublicKeyData(seed: 0x01)
        let key2 = makeTestPublicKeyData(seed: 0x02)

        try await verifier.verify(hostname: "hostA.example.com", port: 22, keyType: "ssh-ed25519", publicKeyData: key1)
        try await verifier.verify(hostname: "hostB.example.com", port: 22, keyType: "ssh-ed25519", publicKeyData: key2)

        let storedA = try await store.lookup(hostname: "hostA.example.com", port: 22, keyType: "ssh-ed25519")
        let storedB = try await store.lookup(hostname: "hostB.example.com", port: 22, keyType: "ssh-ed25519")

        #expect(storedA?.publicKeyData == key1)
        #expect(storedB?.publicKeyData == key2)
        #expect(storedA?.publicKeyData != storedB?.publicKeyData)
    }

    @Test func sameHostDifferentPortsAreIndependent() async throws {
        let store = try makeStore()
        let verifier = HostKeyVerifier(store: store)

        let key1 = makeTestPublicKeyData(seed: 0x03)
        let key2 = makeTestPublicKeyData(seed: 0x04)

        try await verifier.verify(hostname: "shared.example.com", port: 22, keyType: "ssh-ed25519", publicKeyData: key1)
        try await verifier.verify(hostname: "shared.example.com", port: 2222, keyType: "ssh-ed25519", publicKeyData: key2)

        let stored22 = try await store.lookup(hostname: "shared.example.com", port: 22, keyType: "ssh-ed25519")
        let stored2222 = try await store.lookup(hostname: "shared.example.com", port: 2222, keyType: "ssh-ed25519")

        #expect(stored22?.publicKeyData == key1)
        #expect(stored2222?.publicKeyData == key2)
    }

    // MARK: - Fingerprint Consistency

    @Test func fingerprintIsConsistentAcrossVerifications() async throws {
        let store = try makeStore()
        let verifier = HostKeyVerifier(store: store)

        let pubKeyData = makeTestPublicKeyData(seed: 0xEE)
        let directFingerprint = FingerprintFormatter.sha256Fingerprint(of: pubKeyData)

        try await verifier.verify(hostname: "fp1.example.com", port: 22, keyType: "ssh-ed25519", publicKeyData: pubKeyData)
        try await verifier.verify(hostname: "fp2.example.com", port: 22, keyType: "ssh-ed25519", publicKeyData: pubKeyData)

        let stored1 = try await store.lookup(hostname: "fp1.example.com", port: 22, keyType: "ssh-ed25519")
        let stored2 = try await store.lookup(hostname: "fp2.example.com", port: 22, keyType: "ssh-ed25519")

        #expect(stored1?.fingerprint == directFingerprint)
        #expect(stored2?.fingerprint == directFingerprint)
    }

    // MARK: - Revoke and Re-trust

    @Test func revokeAndRetrust() async throws {
        let store = try makeStore()
        let verifier = HostKeyVerifier(store: store)

        let key1 = makeTestPublicKeyData(seed: 0xF0)
        try await verifier.verify(hostname: "revoke.example.com", port: 22, keyType: "ssh-ed25519", publicKeyData: key1)

        let stored1 = try await store.lookup(hostname: "revoke.example.com", port: 22, keyType: "ssh-ed25519")
        #expect(stored1 != nil)

        try await store.revoke(hostname: "revoke.example.com", port: 22)

        let stored2 = try await store.lookup(hostname: "revoke.example.com", port: 22, keyType: "ssh-ed25519")
        #expect(stored2 == nil)

        let key2 = makeTestPublicKeyData(seed: 0xF1)
        try await verifier.verify(hostname: "revoke.example.com", port: 22, keyType: "ssh-ed25519", publicKeyData: key2)

        let stored3 = try await store.lookup(hostname: "revoke.example.com", port: 22, keyType: "ssh-ed25519")
        #expect(stored3?.publicKeyData == key2)
    }
}
