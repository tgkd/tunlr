import XCTest
@testable import DivineMarssh

final class ModelTests: XCTestCase {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - SSHAuthMethod round-trips

    func testAuthMethodSecureEnclaveRoundTrip() throws {
        let method = SSHAuthMethod.secureEnclaveKey(keyTag: "com.test.key1")
        let data = try encoder.encode(method)
        let decoded = try decoder.decode(SSHAuthMethod.self, from: data)
        XCTAssertEqual(decoded, method)
    }

    func testAuthMethodImportedKeyRoundTrip() throws {
        let id = UUID()
        let method = SSHAuthMethod.importedKey(keyID: id)
        let data = try encoder.encode(method)
        let decoded = try decoder.decode(SSHAuthMethod.self, from: data)
        XCTAssertEqual(decoded, method)
    }

    func testAuthMethodPasswordRoundTrip() throws {
        let method = SSHAuthMethod.password
        let data = try encoder.encode(method)
        let decoded = try decoder.decode(SSHAuthMethod.self, from: data)
        XCTAssertEqual(decoded, method)
    }

    // MARK: - SSHHostKey round-trip

    func testHostKeyRoundTrip() throws {
        let hostKey = SSHHostKey(
            hostname: "example.com",
            port: 22,
            keyType: "ssh-ed25519",
            publicKeyData: Data([0x01, 0x02, 0x03]),
            fingerprint: "SHA256:abc123",
            firstSeenDate: Date(timeIntervalSince1970: 1700000000)
        )
        let data = try encoder.encode(hostKey)
        let decoded = try decoder.decode(SSHHostKey.self, from: data)
        XCTAssertEqual(decoded, hostKey)
        XCTAssertEqual(decoded.id, "example.com:22:ssh-ed25519")
    }

    // MARK: - SSHIdentity round-trip

    func testIdentityRoundTrip() throws {
        let identity = SSHIdentity(
            id: UUID(),
            label: "My Key",
            keyType: "ecdsa-sha2-nistp256",
            publicKeyData: Data([0xAA, 0xBB]),
            createdAt: Date(timeIntervalSince1970: 1700000000),
            storageType: .secureEnclave
        )
        let data = try encoder.encode(identity)
        let decoded = try decoder.decode(SSHIdentity.self, from: data)
        XCTAssertEqual(decoded, identity)
    }

    func testIdentityKeychainStorageType() throws {
        let identity = SSHIdentity(
            id: UUID(),
            label: "Imported",
            keyType: "ssh-ed25519",
            publicKeyData: Data([0x01]),
            createdAt: Date(timeIntervalSince1970: 1700000000),
            storageType: .keychain
        )
        let data = try encoder.encode(identity)
        let decoded = try decoder.decode(SSHIdentity.self, from: data)
        XCTAssertEqual(decoded.storageType, .keychain)
    }

    // MARK: - SSHConnectionProfile round-trip

    func testConnectionProfileRoundTrip() throws {
        let profile = SSHConnectionProfile(
            host: "192.168.1.1",
            port: 2222,
            username: "admin",
            authMethod: .password,
            lastConnected: Date(timeIntervalSince1970: 1700000000),
            autoReconnect: true
        )
        let data = try encoder.encode(profile)
        let decoded = try decoder.decode(SSHConnectionProfile.self, from: data)
        XCTAssertEqual(decoded, profile)
    }

    func testConnectionProfileDefaultValues() {
        let profile = SSHConnectionProfile(
            host: "server.local",
            username: "user",
            authMethod: .secureEnclaveKey(keyTag: "tag")
        )
        XCTAssertEqual(profile.port, 22)
        XCTAssertNil(profile.lastConnected)
        XCTAssertFalse(profile.autoReconnect)
    }

    func testConnectionProfileWithImportedKey() throws {
        let keyID = UUID()
        let profile = SSHConnectionProfile(
            host: "host.com",
            username: "deploy",
            authMethod: .importedKey(keyID: keyID)
        )
        let data = try encoder.encode(profile)
        let decoded = try decoder.decode(SSHConnectionProfile.self, from: data)
        XCTAssertEqual(decoded.authMethod, .importedKey(keyID: keyID))
    }

    // MARK: - Sendable conformance (compile-time check)

    func testModelsSendable() {
        let profile: any Sendable = SSHConnectionProfile(
            host: "h", username: "u", authMethod: .password
        )
        let hostKey: any Sendable = SSHHostKey(
            hostname: "h", port: 22, keyType: "t",
            publicKeyData: Data(), fingerprint: "f",
            firstSeenDate: Date()
        )
        let identity: any Sendable = SSHIdentity(
            id: UUID(), label: "l", keyType: "t",
            publicKeyData: Data(), createdAt: Date(),
            storageType: .secureEnclave
        )
        let method: any Sendable = SSHAuthMethod.password
        XCTAssertNotNil(profile)
        XCTAssertNotNil(hostKey)
        XCTAssertNotNil(identity)
        XCTAssertNotNil(method)
    }
}
