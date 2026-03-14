import Foundation

actor KeyManager {
    let secureEnclaveManager: SecureEnclaveKeyManager
    let keychainManager: KeychainKeyManager

    init(secureEnclaveManager: SecureEnclaveKeyManager, keychainManager: KeychainKeyManager) {
        self.secureEnclaveManager = secureEnclaveManager
        self.keychainManager = keychainManager
    }

    func listAllKeys() async -> [SSHIdentity] {
        let seKeys: [SSHIdentity] = [] // SE keys don't have a list API; tracked via profiles
        let importedKeys = await keychainManager.listKeys()
        return seKeys + importedKeys
    }

    func deleteKey(identity: SSHIdentity) async {
        switch identity.storageType {
        case .secureEnclave:
            await secureEnclaveManager.deleteKey(tag: identity.id.uuidString)
        case .keychain:
            await keychainManager.deleteKey(id: identity.id)
        }
    }

    func authenticator(for authMethod: SSHAuthMethod) -> any SSHAuthenticatable {
        switch authMethod {
        case .secureEnclaveKey(let keyTag):
            return SEKeyAuthenticator(keyTag: keyTag, manager: secureEnclaveManager)
        case .importedKey(let keyID):
            return ImportedKeyAuthenticator(keyID: keyID, manager: keychainManager)
        case .password:
            fatalError("Password auth does not use SSHAuthenticatable")
        }
    }

    func generateSecureEnclaveKey(label: String) async throws -> SSHIdentity {
        try await secureEnclaveManager.generateKey(label: label)
    }

    func importKey(pemData: Data, label: String, passphrase: String? = nil) async throws -> SSHIdentity {
        try await keychainManager.importKey(pemData: pemData, label: label, passphrase: passphrase)
    }
}
