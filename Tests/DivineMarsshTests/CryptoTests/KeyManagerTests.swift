import Testing
import Foundation
import CryptoKit
@testable import DivineMarssh

struct KeyManagerTests {

    // MARK: - Mock Authenticator

    struct MockAuthenticator: SSHAuthenticatable {
        let response: Data

        func authenticate(sessionHash: Data) async throws -> Data {
            response
        }
    }

    struct FailingAuthenticator: SSHAuthenticatable {
        func authenticate(sessionHash: Data) async throws -> Data {
            throw MockError.authFailed
        }
    }

    enum MockError: Error {
        case authFailed
    }

    // MARK: - SSHAuthenticatable Protocol Tests

    @Test func mockAuthenticatorReturnsExpectedData() async throws {
        let expected = Data([0x01, 0x02, 0x03])
        let auth = MockAuthenticator(response: expected)
        let result = try await auth.authenticate(sessionHash: Data("test".utf8))
        #expect(result == expected)
    }

    @Test func failingAuthenticatorThrows() async {
        let auth = FailingAuthenticator()
        await #expect(throws: MockError.self) {
            try await auth.authenticate(sessionHash: Data("test".utf8))
        }
    }

    // MARK: - KeyManager Facade Routing Tests

    @Test func facadeRoutesToSEAuthenticatorForSecureEnclaveKey() async throws {
        let (manager, tempDir) = try createTestKeyManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let auth = await manager.authenticator(for: .secureEnclaveKey(keyTag: "test-tag"))
        #expect(auth is SEKeyAuthenticator)
    }

    @Test func facadeRoutesToImportedAuthenticatorForImportedKey() async throws {
        let (manager, tempDir) = try createTestKeyManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let keyID = UUID()
        let auth = await manager.authenticator(for: .importedKey(keyID: keyID))
        #expect(auth is ImportedKeyAuthenticator)
    }

    @Test func facadeListsImportedKeys() async throws {
        let (manager, tempDir) = try createTestKeyManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let key = Curve25519.Signing.PrivateKey()
        let pem = Self.buildEd25519PEM(key)
        _ = try await manager.importKey(pemData: pem, label: "facade test")

        let allKeys = await manager.listAllKeys()
        #expect(allKeys.count == 1)
        #expect(allKeys.first?.label == "facade test")
    }

    @Test func facadeDeletesImportedKey() async throws {
        let (manager, tempDir) = try createTestKeyManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let key = Curve25519.Signing.PrivateKey()
        let pem = Self.buildEd25519PEM(key)
        let identity = try await manager.importKey(pemData: pem, label: "to delete")

        await manager.deleteKey(identity: identity)
        let allKeys = await manager.listAllKeys()
        #expect(allKeys.isEmpty)
    }

    @Test func facadeImportKeyDelegatesToKeychainManager() async throws {
        let (manager, tempDir) = try createTestKeyManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let key = P256.Signing.PrivateKey()
        let pem = Self.buildECDSAPEM(key)
        let identity = try await manager.importKey(pemData: pem, label: "ecdsa key")

        #expect(identity.keyType == "ecdsa-sha2-nistp256")
        #expect(identity.storageType == .keychain)
    }

    // MARK: - DER Signature Structure Tests

    @Test func derSignatureFromEd25519HasCorrectBlobFormat() async throws {
        let key = Curve25519.Signing.PrivateKey()
        let sessionHash = Data("session-hash-data".utf8)
        let signature = try key.signature(for: sessionHash)

        let blob = encodeSSHSignatureBlob(algorithm: "ssh-ed25519", signature: signature)

        var offset = 0
        let algName = readSSHString(from: blob, offset: &offset)
        let sigData = readSSHData(from: blob, offset: &offset)

        #expect(algName == "ssh-ed25519")
        #expect(sigData == signature)
        #expect(offset == blob.count)
    }

    @Test func derSignatureFromECDSAHasCorrectDERStructure() {
        let key = P256.Signing.PrivateKey()
        let data = Data("test-data".utf8)
        let signature = try! key.signature(for: data)
        let p1363 = signature.rawRepresentation

        let der = SecureEnclaveKeyManager.p1363ToDER(signature: p1363)

        // Verify DER SEQUENCE structure
        #expect(der[0] == 0x30) // SEQUENCE tag

        var offset = 1
        let seqLen = readASN1Length(from: der, offset: &offset)
        #expect(seqLen > 0)

        // First INTEGER (r)
        #expect(der[offset] == 0x02)
        offset += 1
        let rLen = readASN1Length(from: der, offset: &offset)
        #expect(rLen > 0 && rLen <= 33)
        offset += rLen

        // Second INTEGER (s)
        #expect(der[offset] == 0x02)
        offset += 1
        let sLen = readASN1Length(from: der, offset: &offset)
        #expect(sLen > 0 && sLen <= 33)
        offset += sLen

        #expect(offset == der.count)
    }

    @Test func ecdsaSignatureBlobContainsAlgorithmAndDER() {
        let key = P256.Signing.PrivateKey()
        let data = Data("blob-test".utf8)
        let signature = try! key.signature(for: data)
        let der = SecureEnclaveKeyManager.p1363ToDER(signature: signature.rawRepresentation)
        let blob = SecureEnclaveKeyManager.encodeSSHSignatureBlob(derSignature: der)

        var offset = 0
        let algName = readSSHString(from: blob, offset: &offset)
        let sigData = readSSHData(from: blob, offset: &offset)

        #expect(algName == "ecdsa-sha2-nistp256")
        #expect(sigData == der)
        #expect(offset == blob.count)
    }

    @Test func importedKeyAuthenticatorSignsEd25519Correctly() async throws {
        let (_, tempDir, keychainManager) = try createTestKeychainManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let key = Curve25519.Signing.PrivateKey()
        let pem = Self.buildEd25519PEM(key)
        let identity = try await keychainManager.importKey(pemData: pem, label: "sign test")

        let authenticator = ImportedKeyAuthenticator(keyID: identity.id, manager: keychainManager)
        let sessionHash = Data("session-hash".utf8)
        let blob = try await authenticator.authenticate(sessionHash: sessionHash)

        var offset = 0
        let algName = readSSHString(from: blob, offset: &offset)
        let sigData = readSSHData(from: blob, offset: &offset)

        #expect(algName == "ssh-ed25519")
        let isValid = key.publicKey.isValidSignature(sigData, for: sessionHash)
        #expect(isValid)

        await keychainManager.deleteKey(id: identity.id)
    }

    @Test func importedKeyAuthenticatorSignsECDSACorrectly() async throws {
        let (_, tempDir, keychainManager) = try createTestKeychainManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let key = P256.Signing.PrivateKey()
        let pem = Self.buildECDSAPEM(key)
        let identity = try await keychainManager.importKey(pemData: pem, label: "ecdsa sign")

        let authenticator = ImportedKeyAuthenticator(keyID: identity.id, manager: keychainManager)
        let sessionHash = Data("ecdsa-session".utf8)
        let blob = try await authenticator.authenticate(sessionHash: sessionHash)

        var offset = 0
        let algName = readSSHString(from: blob, offset: &offset)
        let sigDER = readSSHData(from: blob, offset: &offset)

        #expect(algName == "ecdsa-sha2-nistp256")
        #expect(sigDER[0] == 0x30) // DER SEQUENCE

        await keychainManager.deleteKey(id: identity.id)
    }

    // MARK: - Helpers

    private func createTestKeyManager() throws -> (KeyManager, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeyManagerTest-\(UUID().uuidString)")
        let keychainManager = try KeychainKeyManager(
            directory: tempDir,
            keychainServiceName: "com.divinemarssh.test.\(UUID().uuidString)",
            useBiometricProtection: false
        )
        let seManager = SecureEnclaveKeyManager()
        let manager = KeyManager(secureEnclaveManager: seManager, keychainManager: keychainManager)
        return (manager, tempDir)
    }

    private func createTestKeychainManager() throws -> (String, URL, KeychainKeyManager) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeyManagerTest-\(UUID().uuidString)")
        let serviceName = "com.divinemarssh.test.\(UUID().uuidString)"
        let manager = try KeychainKeyManager(
            directory: tempDir,
            keychainServiceName: serviceName,
            useBiometricProtection: false
        )
        return (serviceName, tempDir, manager)
    }

    private func encodeSSHSignatureBlob(algorithm: String, signature: Data) -> Data {
        var blob = Data()
        var length = UInt32(algorithm.utf8.count).bigEndian
        blob.append(Data(bytes: &length, count: 4))
        blob.append(Data(algorithm.utf8))
        var sigLength = UInt32(signature.count).bigEndian
        blob.append(Data(bytes: &sigLength, count: 4))
        blob.append(signature)
        return blob
    }

    private func readSSHString(from data: Data, offset: inout Int) -> String {
        let bytes = readSSHData(from: data, offset: &offset)
        return String(data: bytes, encoding: .utf8) ?? ""
    }

    private func readSSHData(from data: Data, offset: inout Int) -> Data {
        let length = Int(data[offset]) << 24
            | Int(data[offset + 1]) << 16
            | Int(data[offset + 2]) << 8
            | Int(data[offset + 3])
        offset += 4
        let result = data[offset..<(offset + length)]
        offset += length
        return Data(result)
    }

    private func readASN1Length(from data: Data, offset: inout Int) -> Int {
        let first = Int(data[offset])
        offset += 1
        if first < 128 { return first }
        if first == 0x81 {
            let len = Int(data[offset])
            offset += 1
            return len
        }
        let len = Int(data[offset]) << 8 | Int(data[offset + 1])
        offset += 2
        return len
    }

    // MARK: - PEM Building Helpers

    static func buildEd25519PEM(_ key: Curve25519.Signing.PrivateKey) -> Data {
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

    static func buildECDSAPEM(_ key: P256.Signing.PrivateKey) -> Data {
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

    private static func padTo8(_ data: inout [UInt8]) {
        let remainder = data.count % 8
        if remainder != 0 {
            let padLen = 8 - remainder
            for i in 1...padLen { data.append(UInt8(i)) }
        }
    }

    private static func wrapPEM(_ blob: [UInt8]) -> Data {
        let base64 = Data(blob).base64EncodedString(
            options: [.lineLength76Characters, .endLineWithLineFeed]
        )
        return Data("-----BEGIN OPENSSH PRIVATE KEY-----\n\(base64)\n-----END OPENSSH PRIVATE KEY-----\n".utf8)
    }
}
