import XCTest
@testable import DivineMarssh

final class KnownHostsStoreTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDown() {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        super.tearDown()
    }

    private func makeStore() throws -> KnownHostsStore {
        try KnownHostsStore(directory: tempDir)
    }

    private func makeHostKey(
        hostname: String = "example.com",
        port: UInt16 = 22,
        keyType: String = "ssh-ed25519",
        publicKeyData: Data? = nil,
        fingerprint: String = "SHA256:testfingerprint"
    ) -> SSHHostKey {
        SSHHostKey(
            hostname: hostname,
            port: port,
            keyType: keyType,
            publicKeyData: publicKeyData ?? Data(repeating: 0xAB, count: 32),
            fingerprint: fingerprint,
            firstSeenDate: Date()
        )
    }

    // MARK: - Trust and Lookup

    func testTrustAndLookup() async throws {
        let store = try makeStore()
        let hostKey = makeHostKey()

        try await store.trust(hostKey: hostKey)
        let found = await store.lookup(hostname: "example.com", port: 22, keyType: "ssh-ed25519")

        XCTAssertNotNil(found)
        XCTAssertEqual(found?.hostname, "example.com")
        XCTAssertEqual(found?.port, 22)
        XCTAssertEqual(found?.keyType, "ssh-ed25519")
        XCTAssertEqual(found?.fingerprint, "SHA256:testfingerprint")
    }

    func testLookupReturnsNilForUnknownHost() async throws {
        let store = try makeStore()
        let found = await store.lookup(hostname: "unknown.host", port: 22, keyType: "ssh-ed25519")
        XCTAssertNil(found)
    }

    func testLookupMatchesAllFields() async throws {
        let store = try makeStore()
        let hostKey = makeHostKey(hostname: "host.com", port: 2222, keyType: "ecdsa-sha2-nistp256")

        try await store.trust(hostKey: hostKey)

        let wrongPort = await store.lookup(hostname: "host.com", port: 22, keyType: "ecdsa-sha2-nistp256")
        XCTAssertNil(wrongPort)
        let wrongType = await store.lookup(hostname: "host.com", port: 2222, keyType: "ssh-ed25519")
        XCTAssertNil(wrongType)
        let wrongHost = await store.lookup(hostname: "other.com", port: 2222, keyType: "ecdsa-sha2-nistp256")
        XCTAssertNil(wrongHost)
        let correct = await store.lookup(hostname: "host.com", port: 2222, keyType: "ecdsa-sha2-nistp256")
        XCTAssertNotNil(correct)
    }

    // MARK: - Trust replaces existing

    func testTrustReplacesExistingKeyForSameHostPortType() async throws {
        let store = try makeStore()
        let key1 = makeHostKey(publicKeyData: Data([1, 2, 3]), fingerprint: "fp1")
        let key2 = makeHostKey(publicKeyData: Data([4, 5, 6]), fingerprint: "fp2")

        try await store.trust(hostKey: key1)
        try await store.trust(hostKey: key2)

        let all = await store.allHostKeys()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.fingerprint, "fp2")
        XCTAssertEqual(all.first?.publicKeyData, Data([4, 5, 6]))
    }

    // MARK: - Multiple hosts

    func testMultipleHosts() async throws {
        let store = try makeStore()

        try await store.trust(hostKey: makeHostKey(hostname: "host1.com"))
        try await store.trust(hostKey: makeHostKey(hostname: "host2.com"))
        try await store.trust(hostKey: makeHostKey(hostname: "host3.com"))

        let all = await store.allHostKeys()
        XCTAssertEqual(all.count, 3)
    }

    // MARK: - Revoke

    func testRevokeRemovesAllKeysForHostPort() async throws {
        let store = try makeStore()

        try await store.trust(hostKey: makeHostKey(hostname: "revoke.me", keyType: "ssh-ed25519"))
        try await store.trust(hostKey: makeHostKey(hostname: "revoke.me", keyType: "ecdsa-sha2-nistp256"))

        try await store.revoke(hostname: "revoke.me", port: 22)

        let all = await store.allHostKeys()
        XCTAssertTrue(all.isEmpty)
    }

    func testRevokeDoesNotAffectOtherHosts() async throws {
        let store = try makeStore()

        try await store.trust(hostKey: makeHostKey(hostname: "keep.me"))
        try await store.trust(hostKey: makeHostKey(hostname: "revoke.me"))

        try await store.revoke(hostname: "revoke.me", port: 22)

        let all = await store.allHostKeys()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.hostname, "keep.me")
    }

    func testRevokeNonexistentIsNoOp() async throws {
        let store = try makeStore()
        try await store.revoke(hostname: "nonexistent.host", port: 22)
        let all = await store.allHostKeys()
        XCTAssertTrue(all.isEmpty)
    }

    // MARK: - Persistence across instances

    func testPersistenceAcrossInstances() async throws {
        let store1 = try makeStore()
        try await store1.trust(hostKey: makeHostKey(hostname: "persistent.host"))

        let store2 = try KnownHostsStore(directory: tempDir)
        let all = await store2.allHostKeys()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.hostname, "persistent.host")
    }

    // MARK: - Mismatch detection

    func testMismatchDetection() async throws {
        let store = try makeStore()
        let originalData = Data([1, 2, 3, 4, 5])
        let mismatchData = Data([6, 7, 8, 9, 10])

        try await store.trust(hostKey: makeHostKey(publicKeyData: originalData, fingerprint: "fp-original"))

        let stored = await store.lookup(hostname: "example.com", port: 22, keyType: "ssh-ed25519")
        XCTAssertNotNil(stored)
        XCTAssertEqual(stored?.publicKeyData, originalData)
        XCTAssertNotEqual(stored?.publicKeyData, mismatchData)
    }

    // MARK: - iCloud backup exclusion

    func testFileExcludedFromBackup() async throws {
        let store = try makeStore()
        try await store.trust(hostKey: makeHostKey())

        let fileURL = tempDir.appendingPathComponent("known_hosts.json")
        let resourceValues = try fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(resourceValues.isExcludedFromBackup, true)
    }
}
