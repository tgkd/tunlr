import Testing
import Foundation
import CryptoKit
@testable import DivineMarssh

struct KeychainKeyManagerTests {

    // MARK: - PEM Parsing: Ed25519

    @Test func parsePEMEd25519ProducesCorrectKeyType() throws {
        let key = Curve25519.Signing.PrivateKey()
        let pem = Self.buildEd25519PEM(key)
        let parsed = try KeychainKeyManager.parsePEM(pem)
        #expect(parsed.keyType == "ssh-ed25519")
    }

    @Test func parsePEMEd25519ExtractsCorrectPublicKey() throws {
        let key = Curve25519.Signing.PrivateKey()
        let pem = Self.buildEd25519PEM(key)
        let parsed = try KeychainKeyManager.parsePEM(pem)
        #expect(parsed.publicKeyData == Data(key.publicKey.rawRepresentation))
    }

    @Test func parsePEMEd25519ExtractsCorrectPrivateKey() throws {
        let key = Curve25519.Signing.PrivateKey()
        let pem = Self.buildEd25519PEM(key)
        let parsed = try KeychainKeyManager.parsePEM(pem)
        #expect(parsed.privateKeyData == Data(key.rawRepresentation))
    }

    @Test func parsePEMEd25519RoundTrip() throws {
        let key = Curve25519.Signing.PrivateKey()
        let pem = Self.buildEd25519PEM(key)
        let parsed = try KeychainKeyManager.parsePEM(pem)
        let restored = try Curve25519.Signing.PrivateKey(rawRepresentation: parsed.privateKeyData)
        #expect(restored.publicKey.rawRepresentation == key.publicKey.rawRepresentation)
    }

    // MARK: - PEM Parsing: ECDSA

    @Test func parsePEMECDSAProducesCorrectKeyType() throws {
        let key = P256.Signing.PrivateKey()
        let pem = Self.buildECDSAPEM(key)
        let parsed = try KeychainKeyManager.parsePEM(pem)
        #expect(parsed.keyType == "ecdsa-sha2-nistp256")
    }

    @Test func parsePEMECDSAExtractsCorrectPublicKey() throws {
        let key = P256.Signing.PrivateKey()
        let pem = Self.buildECDSAPEM(key)
        let parsed = try KeychainKeyManager.parsePEM(pem)
        #expect(parsed.publicKeyData == Data(key.publicKey.x963Representation))
    }

    @Test func parsePEMECDSAExtractsCorrectPrivateKey() throws {
        let key = P256.Signing.PrivateKey()
        let pem = Self.buildECDSAPEM(key)
        let parsed = try KeychainKeyManager.parsePEM(pem)
        #expect(parsed.privateKeyData == Data(key.rawRepresentation))
    }

    @Test func parsePEMECDSARoundTrip() throws {
        let key = P256.Signing.PrivateKey()
        let pem = Self.buildECDSAPEM(key)
        let parsed = try KeychainKeyManager.parsePEM(pem)
        let restored = try P256.Signing.PrivateKey(rawRepresentation: parsed.privateKeyData)
        #expect(restored.publicKey.x963Representation == key.publicKey.x963Representation)
    }

    // MARK: - PEM Parsing: RSA

    @Test func parsePEMRSAProducesCorrectKeyType() throws {
        let pem = Self.buildFakeRSAPEM()
        let parsed = try KeychainKeyManager.parsePEM(pem)
        #expect(parsed.keyType == "ssh-rsa")
    }

    @Test func parsePEMRSAExtractsNonEmptyKeys() throws {
        let pem = Self.buildFakeRSAPEM()
        let parsed = try KeychainKeyManager.parsePEM(pem)
        #expect(!parsed.privateKeyData.isEmpty)
        #expect(!parsed.publicKeyData.isEmpty)
    }

    @Test func parsePEMRSAPrivateDataDecodesAsComponents() throws {
        let pem = Self.buildFakeRSAPEM()
        let parsed = try KeychainKeyManager.parsePEM(pem)
        let components = try JSONDecoder().decode(RSAKeyComponents.self, from: parsed.privateKeyData)
        #expect(components.e == Data([0x01, 0x00, 0x01]))
        #expect(components.n.count == 256)
    }

    // MARK: - PEM Parsing: Error Cases

    @Test func parsePEMInvalidDataThrows() {
        let bad = Data("not a key".utf8)
        #expect(throws: KeychainKeyManager.KeychainKeyError.self) {
            try KeychainKeyManager.parsePEM(bad)
        }
    }

    @Test func parsePEMEmptyDataThrows() {
        #expect(throws: KeychainKeyManager.KeychainKeyError.self) {
            try KeychainKeyManager.parsePEM(Data())
        }
    }

    @Test func parsePEMBadBase64Throws() {
        let bad = Data("-----BEGIN OPENSSH PRIVATE KEY-----\n!!invalid!!\n-----END OPENSSH PRIVATE KEY-----\n".utf8)
        #expect(throws: KeychainKeyManager.KeychainKeyError.self) {
            try KeychainKeyManager.parsePEM(bad)
        }
    }

    @Test func parsePEMEncryptedWithoutPassphraseThrows() throws {
        let pem = Self.buildEncryptedEd25519PEM()
        #expect(throws: KeychainKeyManager.KeychainKeyError.passphraseRequired) {
            try KeychainKeyManager.parsePEM(pem, passphrase: nil)
        }
    }

    // MARK: - Key Import/Load/Delete

    @Test func importKeyCreatesIdentity() async throws {
        let (manager, tempDir) = try Self.createTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let key = Curve25519.Signing.PrivateKey()
        let pem = Self.buildEd25519PEM(key)
        let identity = try await manager.importKey(pemData: pem, label: "test key")

        #expect(identity.keyType == "ssh-ed25519")
        #expect(identity.label == "test key")
        #expect(identity.storageType == .keychain)
    }

    @Test func importKeyAppearsInList() async throws {
        let (manager, tempDir) = try Self.createTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let key = Curve25519.Signing.PrivateKey()
        let pem = Self.buildEd25519PEM(key)
        let identity = try await manager.importKey(pemData: pem, label: "listed key")

        let keys = await manager.listKeys()
        #expect(keys.count == 1)
        #expect(keys.first?.id == identity.id)

        await manager.deleteKey(id: identity.id)
    }

    @Test func loadKeyReturnsStoredData() async throws {
        let (manager, tempDir) = try Self.createTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let key = Curve25519.Signing.PrivateKey()
        let pem = Self.buildEd25519PEM(key)
        let identity = try await manager.importKey(pemData: pem, label: "loadable")

        let loaded = try await manager.loadKey(id: identity.id)
        let stored = try JSONDecoder().decode(StoredKeyData.self, from: loaded)
        #expect(stored.keyType == "ssh-ed25519")
        #expect(stored.privateKeyBytes == Data(key.rawRepresentation))

        await manager.deleteKey(id: identity.id)
    }

    @Test func deleteKeyRemovesFromList() async throws {
        let (manager, tempDir) = try Self.createTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let key = Curve25519.Signing.PrivateKey()
        let pem = Self.buildEd25519PEM(key)
        let identity = try await manager.importKey(pemData: pem, label: "deletable")

        await manager.deleteKey(id: identity.id)

        let keys = await manager.listKeys()
        #expect(keys.isEmpty)
    }

    @Test func deleteKeyMakesLoadThrow() async throws {
        let (manager, tempDir) = try Self.createTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let key = Curve25519.Signing.PrivateKey()
        let pem = Self.buildEd25519PEM(key)
        let identity = try await manager.importKey(pemData: pem, label: "gone")

        await manager.deleteKey(id: identity.id)

        await #expect(throws: KeychainKeyManager.KeychainKeyError.keyNotFound) {
            try await manager.loadKey(id: identity.id)
        }
    }

    @Test func loadNonexistentKeyThrows() async throws {
        let (manager, tempDir) = try Self.createTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await #expect(throws: KeychainKeyManager.KeychainKeyError.keyNotFound) {
            try await manager.loadKey(id: UUID())
        }
    }

    // MARK: - BiometricPolicy Tests

    @Test func biometricPolicyDefaultValues() {
        let policy = BiometricPolicy()
        #expect(policy.reuseDuration == 60)
        #expect(policy.allowPasscodeFallback == true)
    }

    @Test func biometricPolicyCustomValues() {
        let policy = BiometricPolicy(reuseDuration: 120, allowPasscodeFallback: false)
        #expect(policy.reuseDuration == 120)
        #expect(policy.allowPasscodeFallback == false)
    }

    @Test func biometricPolicyCreatesContext() {
        let policy = BiometricPolicy(reuseDuration: 30)
        let context = policy.createContext()
        #expect(context.touchIDAuthenticationAllowableReuseDuration == 30)
    }

    // MARK: - SSH Wire Format Helpers

    @Test func readWriteUInt32RoundTrip() throws {
        var data = [UInt8]()
        KeychainKeyManager.writeUInt32(0xDEADBEEF, to: &data)
        var offset = 0
        let value = try KeychainKeyManager.readUInt32(data, offset: &offset)
        #expect(value == 0xDEADBEEF)
        #expect(offset == 4)
    }

    @Test func readWriteSSHBytesRoundTrip() throws {
        let original: [UInt8] = [1, 2, 3, 4, 5]
        var data = [UInt8]()
        KeychainKeyManager.writeSSHBytes(original, to: &data)
        var offset = 0
        let restored = try KeychainKeyManager.readSSHBytes(data, offset: &offset)
        #expect(restored == original)
    }

    @Test func readWriteSSHStringRoundTrip() throws {
        var data = [UInt8]()
        KeychainKeyManager.writeSSHString("hello", to: &data)
        var offset = 0
        let restored = try KeychainKeyManager.readSSHString(data, offset: &offset)
        #expect(restored == "hello")
    }

    // MARK: - Test Helpers

    private static func createTestManager() throws -> (KeychainKeyManager, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeychainKeyManagerTest-\(UUID().uuidString)")
        let manager = try KeychainKeyManager(
            directory: tempDir,
            keychainServiceName: "com.divinemarssh.test.\(UUID().uuidString)",
            useBiometricProtection: false
        )
        return (manager, tempDir)
    }

    private static func buildEd25519PEM(_ key: Curve25519.Signing.PrivateKey) -> Data {
        var blob = [UInt8]()
        blob.append(contentsOf: "openssh-key-v1\0".utf8)

        KeychainKeyManager.writeSSHString("none", to: &blob)
        KeychainKeyManager.writeSSHString("none", to: &blob)
        KeychainKeyManager.writeSSHBytes([], to: &blob)
        KeychainKeyManager.writeUInt32(1, to: &blob)

        var pubBlob = [UInt8]()
        KeychainKeyManager.writeSSHString("ssh-ed25519", to: &pubBlob)
        KeychainKeyManager.writeSSHBytes(Array(key.publicKey.rawRepresentation), to: &pubBlob)
        KeychainKeyManager.writeSSHBytes(pubBlob, to: &blob)

        var privSection = [UInt8]()
        let check: UInt32 = 12345
        KeychainKeyManager.writeUInt32(check, to: &privSection)
        KeychainKeyManager.writeUInt32(check, to: &privSection)
        KeychainKeyManager.writeSSHString("ssh-ed25519", to: &privSection)
        KeychainKeyManager.writeSSHBytes(Array(key.publicKey.rawRepresentation), to: &privSection)
        var privBytes = Array(key.rawRepresentation)
        privBytes.append(contentsOf: key.publicKey.rawRepresentation)
        KeychainKeyManager.writeSSHBytes(privBytes, to: &privSection)
        KeychainKeyManager.writeSSHString("test", to: &privSection)
        padTo8(&privSection)

        KeychainKeyManager.writeSSHBytes(privSection, to: &blob)
        return wrapPEM(blob)
    }

    private static func buildECDSAPEM(_ key: P256.Signing.PrivateKey) -> Data {
        var blob = [UInt8]()
        blob.append(contentsOf: "openssh-key-v1\0".utf8)

        KeychainKeyManager.writeSSHString("none", to: &blob)
        KeychainKeyManager.writeSSHString("none", to: &blob)
        KeychainKeyManager.writeSSHBytes([], to: &blob)
        KeychainKeyManager.writeUInt32(1, to: &blob)

        var pubBlob = [UInt8]()
        KeychainKeyManager.writeSSHString("ecdsa-sha2-nistp256", to: &pubBlob)
        KeychainKeyManager.writeSSHString("nistp256", to: &pubBlob)
        KeychainKeyManager.writeSSHBytes(Array(key.publicKey.x963Representation), to: &pubBlob)
        KeychainKeyManager.writeSSHBytes(pubBlob, to: &blob)

        var privSection = [UInt8]()
        let check: UInt32 = 54321
        KeychainKeyManager.writeUInt32(check, to: &privSection)
        KeychainKeyManager.writeUInt32(check, to: &privSection)
        KeychainKeyManager.writeSSHString("ecdsa-sha2-nistp256", to: &privSection)
        KeychainKeyManager.writeSSHString("nistp256", to: &privSection)
        KeychainKeyManager.writeSSHBytes(Array(key.publicKey.x963Representation), to: &privSection)
        KeychainKeyManager.writeSSHBytes(Array(key.rawRepresentation), to: &privSection)
        KeychainKeyManager.writeSSHString("test", to: &privSection)
        padTo8(&privSection)

        KeychainKeyManager.writeSSHBytes(privSection, to: &blob)
        return wrapPEM(blob)
    }

    private static func buildFakeRSAPEM() -> Data {
        let fakeE: [UInt8] = [0x01, 0x00, 0x01]
        let fakeN = [UInt8](repeating: 0xAB, count: 256)

        var blob = [UInt8]()
        blob.append(contentsOf: "openssh-key-v1\0".utf8)

        KeychainKeyManager.writeSSHString("none", to: &blob)
        KeychainKeyManager.writeSSHString("none", to: &blob)
        KeychainKeyManager.writeSSHBytes([], to: &blob)
        KeychainKeyManager.writeUInt32(1, to: &blob)

        var pubBlob = [UInt8]()
        KeychainKeyManager.writeSSHString("ssh-rsa", to: &pubBlob)
        KeychainKeyManager.writeSSHBytes(fakeE, to: &pubBlob)
        KeychainKeyManager.writeSSHBytes(fakeN, to: &pubBlob)
        KeychainKeyManager.writeSSHBytes(pubBlob, to: &blob)

        var privSection = [UInt8]()
        let check: UInt32 = 99999
        KeychainKeyManager.writeUInt32(check, to: &privSection)
        KeychainKeyManager.writeUInt32(check, to: &privSection)
        KeychainKeyManager.writeSSHString("ssh-rsa", to: &privSection)
        KeychainKeyManager.writeSSHBytes(fakeN, to: &privSection)
        KeychainKeyManager.writeSSHBytes(fakeE, to: &privSection)
        KeychainKeyManager.writeSSHBytes([UInt8](repeating: 0xCD, count: 256), to: &privSection)
        KeychainKeyManager.writeSSHBytes([UInt8](repeating: 0xEF, count: 128), to: &privSection)
        KeychainKeyManager.writeSSHBytes([UInt8](repeating: 0x12, count: 128), to: &privSection)
        KeychainKeyManager.writeSSHBytes([UInt8](repeating: 0x34, count: 128), to: &privSection)
        KeychainKeyManager.writeSSHString("test@rsa", to: &privSection)
        padTo8(&privSection)

        KeychainKeyManager.writeSSHBytes(privSection, to: &blob)
        return wrapPEM(blob)
    }

    private static func buildEncryptedEd25519PEM() -> Data {
        var blob = [UInt8]()
        blob.append(contentsOf: "openssh-key-v1\0".utf8)

        KeychainKeyManager.writeSSHString("aes256-ctr", to: &blob)
        KeychainKeyManager.writeSSHString("bcrypt", to: &blob)

        var kdfOpts = [UInt8]()
        KeychainKeyManager.writeSSHBytes([UInt8](repeating: 0xAA, count: 16), to: &kdfOpts)
        KeychainKeyManager.writeUInt32(16, to: &kdfOpts)
        KeychainKeyManager.writeSSHBytes(kdfOpts, to: &blob)

        KeychainKeyManager.writeUInt32(1, to: &blob)

        var pubBlob = [UInt8]()
        KeychainKeyManager.writeSSHString("ssh-ed25519", to: &pubBlob)
        KeychainKeyManager.writeSSHBytes([UInt8](repeating: 0, count: 32), to: &pubBlob)
        KeychainKeyManager.writeSSHBytes(pubBlob, to: &blob)

        KeychainKeyManager.writeSSHBytes([UInt8](repeating: 0xBB, count: 128), to: &blob)
        return wrapPEM(blob)
    }

    private static func padTo8(_ data: inout [UInt8]) {
        let remainder = data.count % 8
        if remainder != 0 {
            let padLen = 8 - remainder
            for i in 1...padLen {
                data.append(UInt8(i))
            }
        }
    }

    private static func wrapPEM(_ blob: [UInt8]) -> Data {
        let base64 = Data(blob).base64EncodedString(
            options: [.lineLength76Characters, .endLineWithLineFeed]
        )
        return Data("-----BEGIN OPENSSH PRIVATE KEY-----\n\(base64)\n-----END OPENSSH PRIVATE KEY-----\n".utf8)
    }
}
