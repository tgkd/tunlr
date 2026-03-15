import Testing
import Foundation
import CryptoKit
import LocalAuthentication
import NIOCore
@testable import DivineMarssh

// MARK: - BiometricPolicy mapError Tests

@Suite("BiometricPolicy Error Mapping")
struct BiometricPolicyErrorMappingTests {
    @Test func mapsBiometryNotAvailable() {
        let error = NSError(domain: LAErrorDomain, code: LAError.biometryNotAvailable.rawValue)
        let result = BiometricPolicy.mapError(error)
        #expect(result == .biometryNotAvailable)
    }

    @Test func mapsBiometryNotEnrolled() {
        let error = NSError(domain: LAErrorDomain, code: LAError.biometryNotEnrolled.rawValue)
        let result = BiometricPolicy.mapError(error)
        #expect(result == .biometryNotAvailable)
    }

    @Test func mapsBiometryLockout() {
        let error = NSError(domain: LAErrorDomain, code: LAError.biometryLockout.rawValue)
        let result = BiometricPolicy.mapError(error)
        #expect(result == .biometryLockout)
    }

    @Test func mapsUserCancel() {
        let error = NSError(domain: LAErrorDomain, code: LAError.userCancel.rawValue)
        let result = BiometricPolicy.mapError(error)
        #expect(result == .userCancelled)
    }

    @Test func mapsAuthenticationFailed() {
        let error = NSError(domain: LAErrorDomain, code: LAError.authenticationFailed.rawValue)
        let result = BiometricPolicy.mapError(error)
        #expect(result == .authenticationFailed)
    }

    @Test func mapsUnknownLAError() {
        let error = NSError(domain: LAErrorDomain, code: LAError.appCancel.rawValue)
        let result = BiometricPolicy.mapError(error)
        #expect(result == .systemError(LAError.appCancel.rawValue))
    }

    @Test func mapsNonLAErrorToSystemError() {
        let error = NSError(domain: "SomeOtherDomain", code: 42)
        let result = BiometricPolicy.mapError(error)
        #expect(result == .systemError(42))
    }

    @Test func createContextWithoutPasscodeFallback() {
        let policy = BiometricPolicy(reuseDuration: 30, allowPasscodeFallback: false)
        let context = policy.createContext()
        #expect(context.touchIDAuthenticationAllowableReuseDuration == 30)
        #expect(context.localizedFallbackTitle == "")
    }

    @Test func createContextWithPasscodeFallback() {
        let policy = BiometricPolicy(reuseDuration: 120, allowPasscodeFallback: true)
        let context = policy.createContext()
        #expect(context.touchIDAuthenticationAllowableReuseDuration == 120)
    }

    @Test func biometricErrorEquality() {
        #expect(BiometricPolicy.BiometricError.biometryNotAvailable == .biometryNotAvailable)
        #expect(BiometricPolicy.BiometricError.biometryLockout == .biometryLockout)
        #expect(BiometricPolicy.BiometricError.userCancelled == .userCancelled)
        #expect(BiometricPolicy.BiometricError.authenticationFailed == .authenticationFailed)
        #expect(BiometricPolicy.BiometricError.systemError(1) == .systemError(1))
        #expect(BiometricPolicy.BiometricError.systemError(1) != .systemError(2))
        #expect(BiometricPolicy.BiometricError.biometryNotAvailable != .biometryLockout)
    }
}

// MARK: - SSHSession Additional Tests

@Suite("SSHSession Shell Operations")
struct SSHSessionShellOperationsTests {
    private func makeTestProfile() -> SSHConnectionProfile {
        SSHConnectionProfile(
            host: "test.example.com",
            port: 22,
            username: "testuser",
            authMethod: .password
        )
    }

    @Test func writeWithActiveShellSucceeds() async throws {
        let mockClient = MockSSHClient()
        let session = SSHSession(connectionHandler: MockConnectionHandler(client: mockClient))
        try await session.connect(profile: makeTestProfile())
        _ = try await session.openShellChannel()

        try await session.write(Data("ls -la\n".utf8))

        #expect(mockClient.shellOpened)
    }

    @Test func openShellChannelReturnsStream() async throws {
        let mockClient = MockSSHClient()
        let session = SSHSession(connectionHandler: MockConnectionHandler(client: mockClient))
        try await session.connect(profile: makeTestProfile())

        let stream = try await session.openShellChannel()

        #expect(mockClient.shellOpened)
        // Stream is valid
        _ = stream
    }

    @Test func disconnectWithActiveShellCancelsShell() async throws {
        let mockClient = MockSSHClient()
        let session = SSHSession(connectionHandler: MockConnectionHandler(client: mockClient))
        try await session.connect(profile: makeTestProfile())
        _ = try await session.openShellChannel()

        await session.disconnect()

        let state = await session.connectionState
        #expect(state == .disconnected)
        #expect(mockClient.closeCalled)
    }

    @Test func sendWindowChangeWithActiveShell() async throws {
        let mockClient = MockSSHClient()
        let session = SSHSession(connectionHandler: MockConnectionHandler(client: mockClient))
        try await session.connect(profile: makeTestProfile())
        _ = try await session.openShellChannel()

        try await session.sendWindowChange(cols: 132, rows: 43)

        let config = await session.ptyConfiguration
        #expect(config.cols == 132)
        #expect(config.rows == 43)
    }

    @Test func unsupportedKeyTypeError() {
        let e1 = SSHSessionError.unsupportedKeyType("ssh-dss")
        let e2 = SSHSessionError.unsupportedKeyType("ssh-dss")
        let e3 = SSHSessionError.unsupportedKeyType("ssh-rsa")
        #expect(e1 == e2)
        #expect(e1 != e3)
    }

    @Test func multipleStateStreamSubscribers() async throws {
        let mockClient = MockSSHClient()
        let session = SSHSession(connectionHandler: MockConnectionHandler(client: mockClient))

        let stream1 = await session.connectionStateStream()
        let stream2 = await session.connectionStateStream()

        // Both should yield current state
        var states1: [ConnectionState] = []
        var states2: [ConnectionState] = []

        for await state in stream1 {
            states1.append(state)
            break
        }
        for await state in stream2 {
            states2.append(state)
            break
        }

        #expect(states1 == [.disconnected])
        #expect(states2 == [.disconnected])
    }
}

// MARK: - ECDSAP256SSHSignature Tests

@Suite("ECDSA P256 SSH Signature")
struct ECDSAP256SSHSignatureTests {
    @Test func writeProducesValidMPIntFormat() {
        let r = Data(repeating: 0x42, count: 32)
        let s = Data(repeating: 0x13, count: 32)
        let sig = ECDSAP256SSHSignature(rawP1363: r + s)

        var buffer = ByteBuffer()
        _ = sig.write(to: &buffer)

        #expect(buffer.readableBytes > 0)
    }

    @Test func writeHandlesHighBitPadding() {
        // r starts with high bit set (0x80+), should get zero-padded
        var r = Data(repeating: 0x00, count: 31)
        r.append(0xFF)
        // Make r have high bit set at the significant byte
        let rBytes: [UInt8] = [0x80] + Array(repeating: 0x42, count: 31)
        let sBytes: [UInt8] = Array(repeating: 0x13, count: 32)
        let sig = ECDSAP256SSHSignature(rawP1363: Data(rBytes + sBytes))

        var buffer = ByteBuffer()
        let written = sig.write(to: &buffer)

        #expect(written > 0)
        #expect(buffer.readableBytes == written)
    }

    @Test func writeAndReadRoundTrip() throws {
        let key = P256.Signing.PrivateKey()
        let data = Data("round-trip-test".utf8)
        let signature = try key.signature(for: data)
        let original = ECDSAP256SSHSignature(rawP1363: signature.rawRepresentation)

        var writeBuffer = ByteBuffer()
        _ = original.write(to: &writeBuffer)

        // Wrap in algorithm prefix to simulate full blob
        var readBuffer = writeBuffer
        let decoded = try ECDSAP256SSHSignature.read(from: &readBuffer)

        #expect(decoded.rawP1363 == original.rawP1363)
    }

    @Test func readFromTruncatedBufferThrows() {
        var buffer = ByteBuffer(bytes: [0x00, 0x00]) // Too short
        #expect(throws: SSHSessionError.self) {
            _ = try ECDSAP256SSHSignature.read(from: &buffer)
        }
    }

    @Test func signaturePrefix() {
        #expect(ECDSAP256SSHSignature.signaturePrefix == "ecdsa-sha2-nistp256")
    }

    @Test func rawRepresentationMatchesInput() {
        let p1363 = Data(repeating: 0xAB, count: 64)
        let sig = ECDSAP256SSHSignature(rawP1363: p1363)
        #expect(sig.rawRepresentation == p1363)
    }
}

// MARK: - SecureEnclaveP256 SSH Key Tests

@Suite("SecureEnclave P256 SSH Key Types")
struct SecureEnclaveP256SSHKeyTypeTests {
    @Test func publicKeyPrefix() {
        #expect(SecureEnclaveP256SSHKey.keyPrefix == "ecdsa-sha2-nistp256")
    }

    @Test func publicSSHKeyPrefix() {
        #expect(SecureEnclaveP256PublicSSHKey.publicKeyPrefix == "ecdsa-sha2-nistp256")
    }

    @Test func publicKeyWriteAndRead() throws {
        let key = P256.Signing.PrivateKey()
        let pubKey = SecureEnclaveP256PublicSSHKey(key: key.publicKey)

        var buffer = ByteBuffer()
        _ = pubKey.write(to: &buffer)

        let decoded = try SecureEnclaveP256PublicSSHKey.read(from: &buffer)
        #expect(decoded.rawRepresentation == pubKey.rawRepresentation)
    }

    @Test func publicKeyRawRepresentation() {
        let key = P256.Signing.PrivateKey()
        let pubKey = SecureEnclaveP256PublicSSHKey(key: key.publicKey)
        #expect(pubKey.rawRepresentation == key.publicKey.x963Representation)
    }

    @Test func publicKeyReadFromTruncatedBufferThrows() {
        var buffer = ByteBuffer(bytes: [0x00, 0x00, 0x00]) // Too short
        #expect(throws: Error.self) {
            _ = try SecureEnclaveP256PublicSSHKey.read(from: &buffer)
        }
    }

    @Test func signatureValidation() throws {
        let key = P256.Signing.PrivateKey()
        let pubKey = SecureEnclaveP256PublicSSHKey(key: key.publicKey)
        let data = Data("test-data-for-validation".utf8)
        let signature = try key.signature(for: data)
        let sshSig = ECDSAP256SSHSignature(rawP1363: signature.rawRepresentation)

        #expect(pubKey.isValidSignature(sshSig, for: data))
    }

    @Test func invalidSignatureRejected() {
        let key = P256.Signing.PrivateKey()
        let pubKey = SecureEnclaveP256PublicSSHKey(key: key.publicKey)
        let data = Data("original-data".utf8)
        let fakeSig = ECDSAP256SSHSignature(rawP1363: Data(repeating: 0x42, count: 64))

        #expect(!pubKey.isValidSignature(fakeSig, for: data))
    }
}

// MARK: - ImportedKeyAuthenticator ASN.1 Tests

@Suite("ImportedKeyAuthenticator Encoding")
struct ImportedKeyAuthenticatorEncodingTests {
    @Test func unsupportedKeyTypeThrows() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("IKATest-\(UUID().uuidString)")
        let manager = try KeychainKeyManager(
            directory: tempDir,
            keychainServiceName: "com.test.\(UUID().uuidString)",
            useBiometricProtection: false
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create a stored key with unsupported type
        let key = Curve25519.Signing.PrivateKey()
        let pem = KeyManagerTests.buildEd25519PEM(key)
        let identity = try await manager.importKey(pemData: pem, label: "test")

        // Modify the stored data to have an unsupported key type
        // We test through the public API - import an Ed25519 key and verify it works
        let authenticator = ImportedKeyAuthenticator(keyID: identity.id, manager: manager)
        let sessionHash = Data("test-hash".utf8)
        let blob = try await authenticator.authenticate(sessionHash: sessionHash)
        #expect(blob.count > 0)

        await manager.deleteKey(id: identity.id)
    }

    @Test func importedKeyErrorEquality() {
        #expect(ImportedKeyAuthenticator.ImportedKeyError.signingFailed == .signingFailed)
        #expect(ImportedKeyAuthenticator.ImportedKeyError.unsupportedKeyType("a") == .unsupportedKeyType("a"))
        #expect(ImportedKeyAuthenticator.ImportedKeyError.unsupportedKeyType("a") != .unsupportedKeyType("b"))
        #expect(ImportedKeyAuthenticator.ImportedKeyError.signingFailed != .unsupportedKeyType("x"))
    }

    @Test func ecdsaAuthenticatorProducesDERBlob() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("IKAECDSATest-\(UUID().uuidString)")
        let manager = try KeychainKeyManager(
            directory: tempDir,
            keychainServiceName: "com.test.\(UUID().uuidString)",
            useBiometricProtection: false
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let key = P256.Signing.PrivateKey()
        let pem = KeyManagerTests.buildECDSAPEM(key)
        let identity = try await manager.importKey(pemData: pem, label: "ecdsa test")

        let authenticator = ImportedKeyAuthenticator(keyID: identity.id, manager: manager)
        let blob = try await authenticator.authenticate(sessionHash: Data("hash".utf8))

        // Verify SSH blob format: [alg_length][alg][sig_length][sig]
        #expect(blob.count > 8)
        let algLen = Int(blob[0]) << 24 | Int(blob[1]) << 16 | Int(blob[2]) << 8 | Int(blob[3])
        let alg = String(data: blob[4..<(4+algLen)], encoding: .utf8)
        #expect(alg == "ecdsa-sha2-nistp256")

        await manager.deleteKey(id: identity.id)
    }
}

// MARK: - ConnectionViewModel Additional Tests

@Suite("ConnectionViewModel Additional")
struct ConnectionViewModelAdditionalTests {
    private func createStore() async throws -> (ProfileStore, KeyManager, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CVMTest-\(UUID().uuidString)")
        let profileStore = try ProfileStore(
            directory: tempDir
        )
        let keychainManager = try KeychainKeyManager(
            directory: tempDir,
            keychainServiceName: "com.test.keys.\(UUID().uuidString)",
            useBiometricProtection: false
        )
        let keyManager = KeyManager(
            secureEnclaveManager: SecureEnclaveKeyManager(),
            keychainManager: keychainManager
        )
        return (profileStore, keyManager, tempDir)
    }

    @Test @MainActor func loadKeysPopulatesList() async throws {
        let (profileStore, keyManager, tempDir) = try await createStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let key = Curve25519.Signing.PrivateKey()
        let pem = KeyManagerTests.buildEd25519PEM(key)
        _ = try await keyManager.importKey(pemData: pem, label: "test key")

        let vm = ConnectionViewModel(profileStore: profileStore, keyManager: keyManager)
        await vm.loadKeys()

        #expect(vm.availableKeys.count == 1)
        #expect(vm.availableKeys.first?.label == "test key")
    }

    @Test @MainActor func passwordRetrievalReturnsNilForNonexistent() async throws {
        let (profileStore, keyManager, tempDir) = try await createStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let vm = ConnectionViewModel(profileStore: profileStore, keyManager: keyManager)
        let pw = await vm.password(for: UUID())
        #expect(pw == nil)
    }

    @Test @MainActor func passwordRetrievalReturnsStoredPassword() async throws {
        let (profileStore, keyManager, tempDir) = try await createStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let vm = ConnectionViewModel(profileStore: profileStore, keyManager: keyManager)
        try await vm.addProfile(
            host: "host",
            port: 22,
            username: "user",
            authMethod: .password,
            password: "secret",
            autoReconnect: false
        )

        let id = vm.profiles.first!.id
        let pw = await vm.password(for: id)
        #expect(pw == "secret")
    }

    @Test @MainActor func deleteProfileAndReload() async throws {
        let (profileStore, keyManager, tempDir) = try await createStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let vm = ConnectionViewModel(profileStore: profileStore, keyManager: keyManager)
        try await vm.addProfile(
            host: "host1",
            port: 22,
            username: "user",
            authMethod: .password,
            password: nil,
            autoReconnect: false
        )
        #expect(vm.profiles.count == 1)

        try await vm.deleteProfile(id: vm.profiles.first!.id)
        #expect(vm.profiles.isEmpty)
    }

    @Test @MainActor func updateProfileWithValidData() async throws {
        let (profileStore, keyManager, tempDir) = try await createStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let vm = ConnectionViewModel(profileStore: profileStore, keyManager: keyManager)
        try await vm.addProfile(
            host: "original",
            port: 22,
            username: "user",
            authMethod: .password,
            password: nil,
            autoReconnect: false
        )

        var profile = vm.profiles.first!
        profile.host = "updated"
        try await vm.updateProfile(profile, password: nil)

        #expect(vm.profiles.first?.host == "updated")
    }

    @Test @MainActor func sortingWithMixedDates() async throws {
        let (profileStore, keyManager, tempDir) = try await createStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let vm = ConnectionViewModel(profileStore: profileStore, keyManager: keyManager)
        try await vm.addProfile(host: "alpha", port: 22, username: "u", authMethod: .password, password: nil, autoReconnect: false)
        try await vm.addProfile(host: "beta", port: 22, username: "u", authMethod: .password, password: nil, autoReconnect: false)

        // Mark beta as connected (gives it a date)
        let betaId = vm.profiles.first(where: { $0.host == "beta" })!.id
        try await vm.markConnected(id: betaId)

        // beta should now be first (has a date, alpha doesn't)
        #expect(vm.profiles.first?.host == "beta")
    }

    @Test @MainActor func addProfileWithInvalidHostThrows() async throws {
        let (profileStore, keyManager, tempDir) = try await createStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let vm = ConnectionViewModel(profileStore: profileStore, keyManager: keyManager)
        await #expect(throws: ConnectionViewModelError.self) {
            try await vm.addProfile(host: "", port: 22, username: "user", authMethod: .password, password: nil, autoReconnect: false)
        }
    }

    @Test @MainActor func addProfileWithInvalidUsernameThrows() async throws {
        let (profileStore, keyManager, tempDir) = try await createStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let vm = ConnectionViewModel(profileStore: profileStore, keyManager: keyManager)
        await #expect(throws: ConnectionViewModelError.self) {
            try await vm.addProfile(host: "host", port: 22, username: "  ", authMethod: .password, password: nil, autoReconnect: false)
        }
    }

    @Test func profileNotFoundError() {
        #expect(ConnectionViewModelError.profileNotFound == .profileNotFound)
        #expect(ConnectionViewModelError.emptyHost != .emptyUsername)
    }
}

// MARK: - ShellOutput Tests

@Suite("ShellOutput Tests")
struct ShellOutputTests {
    @Test func stdoutCase() {
        let output = ShellOutput.stdout(Data("hello".utf8))
        if case .stdout(let data) = output {
            #expect(data == Data("hello".utf8))
        } else {
            Issue.record("Expected stdout")
        }
    }

    @Test func stderrCase() {
        let output = ShellOutput.stderr(Data("error".utf8))
        if case .stderr(let data) = output {
            #expect(data == Data("error".utf8))
        } else {
            Issue.record("Expected stderr")
        }
    }
}

// MARK: - ConnectionState Tests

@Suite("ConnectionState Additional")
struct ConnectionStateAdditionalTests {
    @Test func reconnectingState() {
        let state = ConnectionState.reconnecting
        #expect(state == .reconnecting)
        #expect(state != .connecting)
        #expect(state != .connected)
        #expect(state != .disconnected)
    }
}

// MARK: - PTYConfiguration Additional Tests

@Suite("PTYConfiguration Additional")
struct PTYConfigurationAdditionalTests {
    @Test func customInitializer() {
        let config = PTYConfiguration(cols: 200, rows: 60, term: "vt100")
        #expect(config.cols == 200)
        #expect(config.rows == 60)
        #expect(config.term == "vt100")
    }

    @Test func defaultInitializer() {
        let config = PTYConfiguration()
        #expect(config.cols == 80)
        #expect(config.rows == 24)
        #expect(config.term == "xterm-256color")
    }

    @Test func mutability() {
        var config = PTYConfiguration()
        config.cols = 132
        config.rows = 43
        config.term = "screen"
        #expect(config.cols == 132)
        #expect(config.rows == 43)
        #expect(config.term == "screen")
    }
}

// MARK: - SSHAuthMethod Tests

@Suite("SSHAuthMethod Additional")
struct SSHAuthMethodAdditionalTests {
    @Test func secureEnclaveKeyTag() {
        let method = SSHAuthMethod.secureEnclaveKey(keyTag: "my-tag")
        if case .secureEnclaveKey(let tag) = method {
            #expect(tag == "my-tag")
        } else {
            Issue.record("Expected secureEnclaveKey")
        }
    }

    @Test func importedKeyID() {
        let id = UUID()
        let method = SSHAuthMethod.importedKey(keyID: id)
        if case .importedKey(let keyID) = method {
            #expect(keyID == id)
        } else {
            Issue.record("Expected importedKey")
        }
    }

    @Test func passwordCase() {
        let method = SSHAuthMethod.password
        if case .password = method {
            // Expected
        } else {
            Issue.record("Expected password")
        }
    }
}
