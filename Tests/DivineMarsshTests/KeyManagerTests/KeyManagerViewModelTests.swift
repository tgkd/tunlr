import Testing
import Foundation
@testable import DivineMarssh

// MARK: - Mock Key Manager

actor MockKeyManagerForVM {
    private var keys: [SSHIdentity] = []
    private var nextGeneratedKey: SSHIdentity?
    private var nextImportedKey: SSHIdentity?
    var deletedIdentities: [SSHIdentity] = []
    var shouldThrowOnGenerate: Bool = false
    var shouldThrowOnImport: Bool = false

    func setNextGeneratedKey(_ key: SSHIdentity) {
        nextGeneratedKey = key
    }

    func setNextImportedKey(_ key: SSHIdentity) {
        nextImportedKey = key
    }

    func addKey(_ key: SSHIdentity) {
        keys.append(key)
    }

    func listAllKeys() -> [SSHIdentity] {
        keys
    }

    func deleteKey(identity: SSHIdentity) {
        keys.removeAll { $0.id == identity.id }
        deletedIdentities.append(identity)
    }

    func generateSecureEnclaveKey(label: String) throws -> SSHIdentity {
        if shouldThrowOnGenerate {
            throw TestKeyManagerError.generationFailed
        }
        let key = nextGeneratedKey ?? SSHIdentity(
            id: UUID(),
            label: label,
            keyType: "ecdsa-sha2-nistp256",
            publicKeyData: Data(repeating: 0x04, count: 65),
            createdAt: Date(),
            storageType: .secureEnclave
        )
        keys.append(key)
        return key
    }

    func importKey(pemData: Data, label: String, passphrase: String?) throws -> SSHIdentity {
        if shouldThrowOnImport {
            throw TestKeyManagerError.importFailed
        }
        let key = nextImportedKey ?? SSHIdentity(
            id: UUID(),
            label: label,
            keyType: "ssh-ed25519",
            publicKeyData: Data(repeating: 0xAB, count: 32),
            createdAt: Date(),
            storageType: .keychain
        )
        keys.append(key)
        return key
    }
}

enum TestKeyManagerError: Error {
    case generationFailed
    case importFailed
}

// MARK: - Load Tests

struct KeyManagerViewModelLoadTests {
    @Test @MainActor func loadKeysPopulatesList() async throws {
        let (vm, keyManager) = await makeViewModel()
        let key = makeSampleIdentity(label: "test-key", storageType: .keychain)
        await keyManager.addKey(key)

        await vm.loadKeys()

        #expect(vm.keys.count == 1)
        #expect(vm.keys.first?.label == "test-key")
    }

    @Test @MainActor func loadKeysWithEmptyStore() async throws {
        let (vm, _) = await makeViewModel()

        await vm.loadKeys()

        #expect(vm.keys.isEmpty)
    }

    @Test @MainActor func loadKeysWithMultipleKeys() async throws {
        let (vm, keyManager) = await makeViewModel()
        let key1 = makeSampleIdentity(label: "key1", storageType: .keychain)
        let key2 = makeSampleIdentity(label: "key2", storageType: .secureEnclave)
        await keyManager.addKey(key1)
        await keyManager.addKey(key2)

        await vm.loadKeys()

        #expect(vm.keys.count == 2)
    }
}

// MARK: - Generate Key Tests

struct KeyManagerViewModelGenerateTests {
    @Test @MainActor func generateSecureEnclaveKeyAddsToList() async throws {
        let (vm, _) = await makeViewModel()

        try await vm.generateSecureEnclaveKey(label: "My SE Key")

        #expect(vm.keys.count == 1)
        #expect(vm.keys.first?.label == "My SE Key")
        #expect(vm.keys.first?.storageType == .secureEnclave)
    }

    @Test @MainActor func generateKeyTracksLoadingState() async throws {
        let (vm, _) = await makeViewModel()

        #expect(!vm.isGeneratingKey)
        try await vm.generateSecureEnclaveKey(label: "test")
        #expect(!vm.isGeneratingKey)
    }

    @Test @MainActor func generateKeyFailureThrows() async throws {
        let (vm, keyManager) = await makeViewModel()
        await keyManager.setShouldThrowOnGenerate(true)

        await #expect(throws: TestKeyManagerError.self) {
            try await vm.generateSecureEnclaveKey(label: "fail")
        }
        #expect(vm.keys.isEmpty)
        #expect(!vm.isGeneratingKey)
    }
}

// MARK: - Import Key Tests

struct KeyManagerViewModelImportTests {
    @Test @MainActor func importKeyAddsToList() async throws {
        let (vm, _) = await makeViewModel()
        let pemData = Data("fake-pem".utf8)

        try await vm.importKey(pemData: pemData, label: "Imported Key", passphrase: nil)

        #expect(vm.keys.count == 1)
        #expect(vm.keys.first?.label == "Imported Key")
        #expect(vm.keys.first?.storageType == .keychain)
    }

    @Test @MainActor func importKeyWithPassphrase() async throws {
        let (vm, _) = await makeViewModel()
        let pemData = Data("encrypted-pem".utf8)

        try await vm.importKey(pemData: pemData, label: "Encrypted Key", passphrase: "secret")

        #expect(vm.keys.count == 1)
    }

    @Test @MainActor func importKeyTracksLoadingState() async throws {
        let (vm, _) = await makeViewModel()

        #expect(!vm.isImportingKey)
        try await vm.importKey(pemData: Data("pem".utf8), label: "test", passphrase: nil)
        #expect(!vm.isImportingKey)
    }

    @Test @MainActor func importKeyFailureThrows() async throws {
        let (vm, keyManager) = await makeViewModel()
        await keyManager.setShouldThrowOnImport(true)

        await #expect(throws: TestKeyManagerError.self) {
            try await vm.importKey(pemData: Data("bad".utf8), label: "fail", passphrase: nil)
        }
        #expect(vm.keys.isEmpty)
        #expect(!vm.isImportingKey)
    }
}

// MARK: - Delete Key Tests

struct KeyManagerViewModelDeleteTests {
    @Test @MainActor func deleteKeyRemovesFromList() async throws {
        let (vm, keyManager) = await makeViewModel()
        let key = makeSampleIdentity(label: "delete-me", storageType: .keychain)
        await keyManager.addKey(key)
        await vm.loadKeys()

        #expect(vm.keys.count == 1)

        await vm.deleteKey(key)

        #expect(vm.keys.isEmpty)
    }

    @Test @MainActor func deleteKeyCallsManager() async throws {
        let (vm, keyManager) = await makeViewModel()
        let key = makeSampleIdentity(label: "delete-me", storageType: .keychain)
        await keyManager.addKey(key)
        await vm.loadKeys()

        await vm.deleteKey(key)

        let deleted = await keyManager.deletedIdentities
        #expect(deleted.count == 1)
        #expect(deleted.first?.id == key.id)
    }

    @Test @MainActor func deleteNonExistentKeyNoOp() async throws {
        let (vm, _) = await makeViewModel()
        let key = makeSampleIdentity(label: "phantom", storageType: .keychain)

        await vm.deleteKey(key)

        #expect(vm.keys.isEmpty)
    }
}

// MARK: - Public Key String Tests

struct KeyManagerViewModelPublicKeyTests {
    @Test @MainActor func publicKeyStringForSEKey() async throws {
        let (vm, _) = await makeViewModel()
        let identity = SSHIdentity(
            id: UUID(),
            label: "se-key",
            keyType: "ecdsa-sha2-nistp256",
            publicKeyData: Data(repeating: 0x04, count: 65),
            createdAt: Date(),
            storageType: .secureEnclave
        )

        let result = vm.publicKeyString(for: identity)

        #expect(result.hasPrefix("ecdsa-sha2-nistp256 "))
        #expect(result.hasSuffix(" se-key"))
    }

    @Test @MainActor func publicKeyStringForImportedKey() async throws {
        let (vm, _) = await makeViewModel()
        let identity = SSHIdentity(
            id: UUID(),
            label: "imported",
            keyType: "ssh-ed25519",
            publicKeyData: Data(repeating: 0xAB, count: 32),
            createdAt: Date(),
            storageType: .keychain
        )

        let result = vm.publicKeyString(for: identity)

        #expect(result.hasPrefix("ssh-ed25519 "))
        #expect(result.hasSuffix(" imported"))
    }
}

// MARK: - Badge Tests

struct KeyManagerViewModelBadgeTests {
    @Test @MainActor func secureEnclaveBadge() async throws {
        let (vm, _) = await makeViewModel()
        let identity = makeSampleIdentity(label: "se", storageType: .secureEnclave, keyType: "ecdsa-sha2-nistp256")

        let badge = vm.keyTypeBadge(for: identity)

        #expect(badge.label == "SE P-256")
        #expect(badge.icon == "cpu")
    }

    @Test @MainActor func ed25519Badge() async throws {
        let (vm, _) = await makeViewModel()
        let identity = makeSampleIdentity(label: "ed", storageType: .keychain, keyType: "ssh-ed25519")

        let badge = vm.keyTypeBadge(for: identity)

        #expect(badge.label == "Ed25519")
        #expect(badge.icon == "key")
    }

    @Test @MainActor func rsaBadge() async throws {
        let (vm, _) = await makeViewModel()
        let identity = makeSampleIdentity(label: "rsa", storageType: .keychain, keyType: "ssh-rsa")

        let badge = vm.keyTypeBadge(for: identity)

        #expect(badge.label == "RSA")
    }

    @Test @MainActor func ecdsaBadge() async throws {
        let (vm, _) = await makeViewModel()
        let identity = makeSampleIdentity(label: "ecdsa", storageType: .keychain, keyType: "ecdsa-sha2-nistp384")

        let badge = vm.keyTypeBadge(for: identity)

        #expect(badge.label == "ECDSA")
    }
}

// MARK: - Error Tests

struct KeyManagerViewModelErrorTests {
    @Test func errorsAreEquatable() {
        #expect(KeyManagerViewModelError.keyNotFound == KeyManagerViewModelError.keyNotFound)
        #expect(KeyManagerViewModelError.deletionFailed == KeyManagerViewModelError.deletionFailed)
        #expect(KeyManagerViewModelError.keyNotFound != KeyManagerViewModelError.deletionFailed)
    }
}

// MARK: - Helpers

private extension MockKeyManagerForVM {
    func setShouldThrowOnGenerate(_ value: Bool) {
        shouldThrowOnGenerate = value
    }

    func setShouldThrowOnImport(_ value: Bool) {
        shouldThrowOnImport = value
    }
}

private func makeSampleIdentity(
    label: String,
    storageType: KeyStorageType,
    keyType: String = "ssh-ed25519"
) -> SSHIdentity {
    SSHIdentity(
        id: UUID(),
        label: label,
        keyType: keyType,
        publicKeyData: Data(repeating: 0x42, count: 32),
        createdAt: Date(),
        storageType: storageType
    )
}

@MainActor
private func makeViewModel() async -> (KeyManagerViewModel, MockKeyManagerForVM) {
    let mockKeyManager = MockKeyManagerForVM()
    let vm = KeyManagerViewModelTestable(mockKeyManager: mockKeyManager)
    return (vm, mockKeyManager)
}

@MainActor
final class KeyManagerViewModelTestable: KeyManagerViewModel {
    private let mockKeyManager: MockKeyManagerForVM

    init(mockKeyManager: MockKeyManagerForVM) {
        self.mockKeyManager = mockKeyManager
        let seManager = SecureEnclaveKeyManager()
        let kcManager = try! KeychainKeyManager()
        let realManager = KeyManager(secureEnclaveManager: seManager, keychainManager: kcManager)
        super.init(keyManager: realManager)
    }

    override func loadKeys() async {
        keys = await mockKeyManager.listAllKeys()
    }

    override func generateSecureEnclaveKey(label: String) async throws {
        isGeneratingKey = true
        defer { isGeneratingKey = false }
        let identity = try await mockKeyManager.generateSecureEnclaveKey(label: label)
        keys.append(identity)
    }

    override func importKey(pemData: Data, label: String, passphrase: String?) async throws {
        isImportingKey = true
        defer { isImportingKey = false }
        let identity = try await mockKeyManager.importKey(pemData: pemData, label: label, passphrase: passphrase)
        keys.append(identity)
    }

    override func deleteKey(_ identity: SSHIdentity) async {
        await mockKeyManager.deleteKey(identity: identity)
        keys.removeAll { $0.id == identity.id }
    }
}
