import Testing
import Foundation
import CryptoKit
@testable import DivineMarssh

private actor Counter {
    var value: Int = 0
    func increment() { value += 1 }
}

private actor FingerprintCollector {
    var values: [String] = []
    func append(_ fp: String) { values.append(fp) }
}

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

    // MARK: - First Connect Accepts (TOFU)

    @Test func firstConnectionRequestsApproval() async throws {
        let store = try makeStore()
        let approvalCounter = Counter()

        let verifier = HostKeyVerifier(store: store) { request in
            await approvalCounter.increment()
            #expect(request.hostname == "newhost.example.com")
            #expect(request.port == 22)
            #expect(request.keyType == "ssh-ed25519")
            #expect(request.fingerprint.hasPrefix("SHA256:"))
            return true
        }

        let pubKeyData = makeTestPublicKeyData()
        try await verifier.verify(
            hostname: "newhost.example.com",
            port: 22,
            keyType: "ssh-ed25519",
            publicKeyData: pubKeyData
        )

        let count = await approvalCounter.value
        #expect(count == 1)

        let stored = await store.lookup(hostname: "newhost.example.com", port: 22, keyType: "ssh-ed25519")
        #expect(stored != nil)
        #expect(stored?.publicKeyData == pubKeyData)
    }

    @Test func firstConnectionRejectedDoesNotStore() async throws {
        let store = try makeStore()

        let verifier = HostKeyVerifier(store: store) { _ in false }

        let pubKeyData = makeTestPublicKeyData()

        await #expect(throws: HostKeyVerificationError.self) {
            try await verifier.verify(
                hostname: "rejected.example.com",
                port: 22,
                keyType: "ssh-ed25519",
                publicKeyData: pubKeyData
            )
        }

        let stored = await store.lookup(hostname: "rejected.example.com", port: 22, keyType: "ssh-ed25519")
        #expect(stored == nil)
    }

    // MARK: - Second Connect Matches

    @Test func secondConnectionWithSameKeySilentlySucceeds() async throws {
        let store = try makeStore()
        let approvalCounter = Counter()

        let verifier = HostKeyVerifier(store: store) { _ in
            await approvalCounter.increment()
            return true
        }

        let pubKeyData = makeTestPublicKeyData()

        try await verifier.verify(
            hostname: "known.example.com",
            port: 22,
            keyType: "ssh-ed25519",
            publicKeyData: pubKeyData
        )
        let count1 = await approvalCounter.value
        #expect(count1 == 1)

        try await verifier.verify(
            hostname: "known.example.com",
            port: 22,
            keyType: "ssh-ed25519",
            publicKeyData: pubKeyData
        )
        let count2 = await approvalCounter.value
        #expect(count2 == 1)
    }

    // MARK: - Changed Key Blocks

    @Test func changedKeyTriggersHardBlock() async throws {
        let store = try makeStore()

        let verifier = HostKeyVerifier(store: store) { _ in true }

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

        let verifier = HostKeyVerifier(store: store) { _ in true }

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

        let stored = await store.lookup(hostname: "preserved.example.com", port: 22, keyType: "ssh-ed25519")
        #expect(stored?.publicKeyData == originalKey)
    }

    // MARK: - Check API (non-throwing)

    @Test func checkReturnsNeedsApprovalForUnknownHost() async throws {
        let store = try makeStore()
        let verifier = HostKeyVerifier(store: store) { _ in true }
        let pubKeyData = makeTestPublicKeyData()

        let result = await verifier.check(
            hostname: "unknown.example.com",
            port: 22,
            keyType: "ssh-ed25519",
            publicKeyData: pubKeyData
        )

        if case .needsUserApproval(let request) = result {
            #expect(request.hostname == "unknown.example.com")
            #expect(request.fingerprint.hasPrefix("SHA256:"))
        } else {
            Issue.record("Expected needsUserApproval, got: \(result)")
        }
    }

    @Test func checkReturnsTrustedForKnownHost() async throws {
        let store = try makeStore()
        let verifier = HostKeyVerifier(store: store) { _ in true }
        let pubKeyData = makeTestPublicKeyData()

        try await verifier.verify(
            hostname: "trusted.example.com",
            port: 22,
            keyType: "ssh-ed25519",
            publicKeyData: pubKeyData
        )

        let result = await verifier.check(
            hostname: "trusted.example.com",
            port: 22,
            keyType: "ssh-ed25519",
            publicKeyData: pubKeyData
        )

        if case .trusted = result {
            // OK
        } else {
            Issue.record("Expected trusted, got: \(result)")
        }
    }

    @Test func checkReturnsMismatchForChangedKey() async throws {
        let store = try makeStore()
        let verifier = HostKeyVerifier(store: store) { _ in true }

        let originalKey = makeTestPublicKeyData(seed: 0x11)
        try await verifier.verify(
            hostname: "mismatch.example.com",
            port: 22,
            keyType: "ssh-ed25519",
            publicKeyData: originalKey
        )

        let changedKey = makeTestPublicKeyData(seed: 0x22)
        let result = await verifier.check(
            hostname: "mismatch.example.com",
            port: 22,
            keyType: "ssh-ed25519",
            publicKeyData: changedKey
        )

        if case .mismatch(let existing, let new) = result {
            #expect(existing != new)
        } else {
            Issue.record("Expected mismatch, got: \(result)")
        }
    }

    // MARK: - Multi-host Verification

    @Test func differentHostsAreIndependent() async throws {
        let store = try makeStore()
        let verifier = HostKeyVerifier(store: store) { _ in true }

        let key1 = makeTestPublicKeyData(seed: 0x01)
        let key2 = makeTestPublicKeyData(seed: 0x02)

        try await verifier.verify(hostname: "hostA.example.com", port: 22, keyType: "ssh-ed25519", publicKeyData: key1)
        try await verifier.verify(hostname: "hostB.example.com", port: 22, keyType: "ssh-ed25519", publicKeyData: key2)

        let storedA = await store.lookup(hostname: "hostA.example.com", port: 22, keyType: "ssh-ed25519")
        let storedB = await store.lookup(hostname: "hostB.example.com", port: 22, keyType: "ssh-ed25519")

        #expect(storedA?.publicKeyData == key1)
        #expect(storedB?.publicKeyData == key2)
        #expect(storedA?.publicKeyData != storedB?.publicKeyData)
    }

    @Test func sameHostDifferentPortsAreIndependent() async throws {
        let store = try makeStore()
        let verifier = HostKeyVerifier(store: store) { _ in true }

        let key1 = makeTestPublicKeyData(seed: 0x03)
        let key2 = makeTestPublicKeyData(seed: 0x04)

        try await verifier.verify(hostname: "shared.example.com", port: 22, keyType: "ssh-ed25519", publicKeyData: key1)
        try await verifier.verify(hostname: "shared.example.com", port: 2222, keyType: "ssh-ed25519", publicKeyData: key2)

        let stored22 = await store.lookup(hostname: "shared.example.com", port: 22, keyType: "ssh-ed25519")
        let stored2222 = await store.lookup(hostname: "shared.example.com", port: 2222, keyType: "ssh-ed25519")

        #expect(stored22?.publicKeyData == key1)
        #expect(stored2222?.publicKeyData == key2)
    }

    // MARK: - Fingerprint Consistency

    @Test func fingerprintIsConsistentAcrossVerifications() async throws {
        let store = try makeStore()
        let collector = FingerprintCollector()

        let verifier = HostKeyVerifier(store: store) { request in
            await collector.append(request.fingerprint)
            return true
        }

        let pubKeyData = makeTestPublicKeyData(seed: 0xEE)

        try await verifier.verify(hostname: "fp1.example.com", port: 22, keyType: "ssh-ed25519", publicKeyData: pubKeyData)
        try await verifier.verify(hostname: "fp2.example.com", port: 22, keyType: "ssh-ed25519", publicKeyData: pubKeyData)

        let fingerprints = await collector.values
        #expect(fingerprints.count == 2)
        #expect(fingerprints[0] == fingerprints[1])

        let directFingerprint = FingerprintFormatter.sha256Fingerprint(of: pubKeyData)
        #expect(fingerprints[0] == directFingerprint)
    }

    // MARK: - Revoke and Re-trust

    @Test func revokeAndRetrust() async throws {
        let store = try makeStore()
        let verifier = HostKeyVerifier(store: store) { _ in true }

        let key1 = makeTestPublicKeyData(seed: 0xF0)
        try await verifier.verify(hostname: "revoke.example.com", port: 22, keyType: "ssh-ed25519", publicKeyData: key1)

        let stored1 = await store.lookup(hostname: "revoke.example.com", port: 22, keyType: "ssh-ed25519")
        #expect(stored1 != nil)

        try await store.revoke(hostname: "revoke.example.com", port: 22)

        let stored2 = await store.lookup(hostname: "revoke.example.com", port: 22, keyType: "ssh-ed25519")
        #expect(stored2 == nil)

        let key2 = makeTestPublicKeyData(seed: 0xF1)
        try await verifier.verify(hostname: "revoke.example.com", port: 22, keyType: "ssh-ed25519", publicKeyData: key2)

        let stored3 = await store.lookup(hostname: "revoke.example.com", port: 22, keyType: "ssh-ed25519")
        #expect(stored3?.publicKeyData == key2)
    }
}
