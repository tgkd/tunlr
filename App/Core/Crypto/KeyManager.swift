import Foundation

actor KeyManager {
    let secureEnclaveManager: SecureEnclaveKeyManager
    let keychainManager: KeychainKeyManager
    private let seMetadataURL: URL
    private var seIdentities: [SSHIdentity]

    init(
        secureEnclaveManager: SecureEnclaveKeyManager,
        keychainManager: KeychainKeyManager,
        directory: URL? = nil
    ) {
        self.secureEnclaveManager = secureEnclaveManager
        self.keychainManager = keychainManager
        let dir = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("DivineMarssh", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.seMetadataURL = dir.appendingPathComponent("se-keys.json")
        if let data = try? Data(contentsOf: seMetadataURL),
           let identities = try? JSONDecoder().decode([SSHIdentity].self, from: data) {
            self.seIdentities = identities
        } else {
            self.seIdentities = []
        }
        Self.excludeFromBackup(url: seMetadataURL)
    }

    func listAllKeys() async -> [SSHIdentity] {
        let importedKeys = await keychainManager.listKeys()
        return seIdentities + importedKeys
    }

    func deleteKey(identity: SSHIdentity) async {
        switch identity.storageType {
        case .secureEnclave:
            await secureEnclaveManager.deleteKey(tag: identity.id.uuidString)
            seIdentities.removeAll { $0.id == identity.id }
            saveSEMetadata()
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
        let identity = try await secureEnclaveManager.generateKey(label: label)
        seIdentities.append(identity)
        saveSEMetadata()
        return identity
    }

    func importKey(pemData: Data, label: String, passphrase: String? = nil) async throws -> SSHIdentity {
        try await keychainManager.importKey(pemData: pemData, label: label, passphrase: passphrase)
    }

    private func saveSEMetadata() {
        if let data = try? JSONEncoder().encode(seIdentities) {
            try? data.write(to: seMetadataURL, options: .atomic)
            Self.excludeFromBackup(url: seMetadataURL)
        }
    }

    private static func excludeFromBackup(url: URL) {
        var resourceURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? resourceURL.setResourceValues(values)
    }
}
