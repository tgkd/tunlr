import Foundation
import Security

actor ProfileStore {
    private let fileURL: URL
    private var profiles: [SSHConnectionProfile] = []
    private let biometricPolicy: BiometricPolicy
    private let useBiometricProtection: Bool

    private static let keychainServiceName = "com.divinemarssh.passwords"

    init(
        directory: URL? = nil,
        biometricPolicy: BiometricPolicy = BiometricPolicy(),
        useBiometricProtection: Bool = true
    ) throws {
        self.biometricPolicy = biometricPolicy
        #if DEBUG
        self.useBiometricProtection = useBiometricProtection
        #else
        self.useBiometricProtection = true
        #endif
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("DivineMarssh", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("profiles.json")
        self.profiles = Self.loadFromDisk(url: fileURL)
        Self.excludeFromBackup(url: fileURL)
    }

    private static func loadFromDisk(url: URL) -> [SSHConnectionProfile] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([SSHConnectionProfile].self, from: data)) ?? []
    }

    private func saveToDisk() throws {
        let data = try JSONEncoder().encode(profiles)
        try data.write(to: fileURL, options: .atomic)
        Self.excludeFromBackup(url: fileURL)
    }

    private static func excludeFromBackup(url: URL) {
        var resourceURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? resourceURL.setResourceValues(values)
    }

    // MARK: - CRUD

    func allProfiles() -> [SSHConnectionProfile] {
        profiles
    }

    func profile(id: UUID) -> SSHConnectionProfile? {
        profiles.first { $0.id == id }
    }

    func addProfile(_ profile: SSHConnectionProfile, password: String? = nil) throws {
        profiles.append(profile)
        if let password, case .password = profile.authMethod {
            try savePassword(password, for: profile.id)
        }
        try saveToDisk()
    }

    func updateProfile(_ profile: SSHConnectionProfile, password: String? = nil) throws {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
            throw ProfileStoreError.profileNotFound
        }
        profiles[index] = profile
        if let password, case .password = profile.authMethod {
            try savePassword(password, for: profile.id)
        }
        try saveToDisk()
    }

    func deleteProfile(id: UUID) throws {
        profiles.removeAll { $0.id == id }
        deletePassword(for: id)
        try saveToDisk()
    }

    func password(for profileID: UUID) -> String? {
        loadPassword(for: profileID)
    }

    // MARK: - Keychain

    private func savePassword(_ password: String, for profileID: UUID) throws {
        let account = profileID.uuidString
        deletePassword(for: profileID)

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainServiceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(password.utf8),
        ]

        if useBiometricProtection,
           let accessControl = SecAccessControlCreateWithFlags(
               nil,
               kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
               .biometryCurrentSet,
               nil
           )
        {
            query[kSecAttrAccessControl as String] = accessControl
        } else {
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ProfileStoreError.keychainError(status)
        }
    }

    private func loadPassword(for profileID: UUID) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainServiceName,
            kSecAttrAccount as String: profileID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if useBiometricProtection {
            let context = biometricPolicy.createContext()
            query[kSecUseAuthenticationContext as String] = context
        }
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    private func deletePassword(for profileID: UUID) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainServiceName,
            kSecAttrAccount as String: profileID.uuidString,
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
}

enum ProfileStoreError: Error, Equatable {
    case profileNotFound
    case keychainError(OSStatus)
}
