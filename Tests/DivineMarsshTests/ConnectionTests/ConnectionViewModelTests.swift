import Testing
import Foundation
@testable import DivineMarssh

// MARK: - Mock Profile Store

actor MockProfileStore {
    private var profiles: [SSHConnectionProfile] = []
    private var passwords: [UUID: String] = [:]

    func allProfiles() -> [SSHConnectionProfile] {
        profiles
    }

    func profile(id: UUID) -> SSHConnectionProfile? {
        profiles.first { $0.id == id }
    }

    func addProfile(_ profile: SSHConnectionProfile, password: String? = nil) {
        profiles.append(profile)
        if let password {
            passwords[profile.id] = password
        }
    }

    func updateProfile(_ profile: SSHConnectionProfile, password: String? = nil) throws {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
            throw ProfileStoreError.profileNotFound
        }
        profiles[index] = profile
        if let password {
            passwords[profile.id] = password
        }
    }

    func deleteProfile(id: UUID) {
        profiles.removeAll { $0.id == id }
        passwords.removeValue(forKey: id)
    }

    func password(for profileID: UUID) -> String? {
        passwords[profileID]
    }
}

// MARK: - Validation Tests

struct ConnectionViewModelValidationTests {
    @Test @MainActor func validFieldsDoNotThrow() throws {
        let vm = try makeViewModel()
        #expect(throws: Never.self) {
            try vm.validateFields(host: "example.com", username: "root", port: 22)
        }
    }

    @Test @MainActor func emptyHostThrows() throws {
        let vm = try makeViewModel()
        #expect(throws: ConnectionViewModelError.self) {
            try vm.validateFields(host: "", username: "root", port: 22)
        }
    }

    @Test @MainActor func whitespaceOnlyHostThrows() throws {
        let vm = try makeViewModel()
        #expect(throws: ConnectionViewModelError.self) {
            try vm.validateFields(host: "   ", username: "root", port: 22)
        }
    }

    @Test @MainActor func emptyUsernameThrows() throws {
        let vm = try makeViewModel()
        #expect(throws: ConnectionViewModelError.self) {
            try vm.validateFields(host: "example.com", username: "", port: 22)
        }
    }

    @Test @MainActor func zeroPortThrows() throws {
        let vm = try makeViewModel()
        #expect(throws: ConnectionViewModelError.self) {
            try vm.validateFields(host: "example.com", username: "root", port: 0)
        }
    }

    @Test @MainActor func customPortIsValid() throws {
        let vm = try makeViewModel()
        #expect(throws: Never.self) {
            try vm.validateFields(host: "example.com", username: "root", port: 2222)
        }
    }

    @MainActor
    private func makeViewModel() throws -> ConnectionViewModel {
        let store = try ProfileStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), useBiometricProtection: false)
        let seManager = SecureEnclaveKeyManager()
        let kcManager = try KeychainKeyManager(useBiometricProtection: false)
        let keyManager = KeyManager(secureEnclaveManager: seManager, keychainManager: kcManager)
        return ConnectionViewModel(profileStore: store, keyManager: keyManager)
    }

    @Test @MainActor func hostTooLongThrows() throws {
        let vm = try makeViewModel()
        let longHost = String(repeating: "a", count: 254)
        #expect(throws: ConnectionViewModelError.hostTooLong) {
            try vm.validateFields(host: longHost, username: "root", port: 22)
        }
    }

    @Test @MainActor func usernameTooLongThrows() throws {
        let vm = try makeViewModel()
        let longUser = String(repeating: "a", count: 129)
        #expect(throws: ConnectionViewModelError.usernameTooLong) {
            try vm.validateFields(host: "example.com", username: longUser, port: 22)
        }
    }

    @Test @MainActor func controlCharsInHostThrows() throws {
        let vm = try makeViewModel()
        #expect(throws: ConnectionViewModelError.invalidHostFormat) {
            try vm.validateFields(host: "host\u{0000}.com", username: "root", port: 22)
        }
    }

    @Test @MainActor func controlCharsInUsernameThrows() throws {
        let vm = try makeViewModel()
        #expect(throws: ConnectionViewModelError.invalidUsernameFormat) {
            try vm.validateFields(host: "example.com", username: "user\u{0007}", port: 22)
        }
    }

    @Test @MainActor func ipv4HostIsValid() throws {
        let vm = try makeViewModel()
        #expect(throws: Never.self) {
            try vm.validateFields(host: "192.168.1.1", username: "root", port: 22)
        }
    }

    @Test @MainActor func ipv6HostIsValid() throws {
        let vm = try makeViewModel()
        #expect(throws: Never.self) {
            try vm.validateFields(host: "[::1]", username: "root", port: 22)
        }
    }

    @Test @MainActor func shellMetacharsInHostThrows() throws {
        let vm = try makeViewModel()
        #expect(throws: ConnectionViewModelError.invalidHostFormat) {
            try vm.validateFields(host: "host;rm -rf /", username: "root", port: 22)
        }
    }

    @Test @MainActor func shellMetacharsInUsernameThrows() throws {
        let vm = try makeViewModel()
        #expect(throws: ConnectionViewModelError.invalidUsernameFormat) {
            try vm.validateFields(host: "example.com", username: "user$(whoami)", port: 22)
        }
    }
}

// MARK: - Profile CRUD Tests

struct ConnectionViewModelCRUDTests {
    @Test @MainActor func addProfileAppearsInList() async throws {
        let (vm, _) = try makeViewModelWithStore()

        try await vm.addProfile(
            host: "example.com",
            port: 22,
            username: "admin",
            authMethod: .password,
            password: "secret",
            autoReconnect: false
        )

        #expect(vm.profiles.count == 1)
        #expect(vm.profiles.first?.host == "example.com")
        #expect(vm.profiles.first?.username == "admin")
    }

    @Test @MainActor func addMultipleProfilesSortedByLastConnected() async throws {
        let (vm, store) = try makeViewModelWithStore()

        let older = SSHConnectionProfile(
            host: "older.example.com",
            username: "user",
            authMethod: .password,
            lastConnected: Date(timeIntervalSince1970: 1000)
        )
        let newer = SSHConnectionProfile(
            host: "newer.example.com",
            username: "user",
            authMethod: .password,
            lastConnected: Date(timeIntervalSince1970: 2000)
        )
        let never = SSHConnectionProfile(
            host: "never.example.com",
            username: "user",
            authMethod: .password
        )

        try await store.addProfile(older)
        try await store.addProfile(newer)
        try await store.addProfile(never)

        await vm.loadProfiles()

        #expect(vm.profiles.count == 3)
        #expect(vm.profiles[0].host == "newer.example.com")
        #expect(vm.profiles[1].host == "older.example.com")
        #expect(vm.profiles[2].host == "never.example.com")
    }

    @Test @MainActor func deleteProfileRemovesFromList() async throws {
        let (vm, _) = try makeViewModelWithStore()

        try await vm.addProfile(
            host: "example.com",
            port: 22,
            username: "admin",
            authMethod: .password,
            password: nil,
            autoReconnect: false
        )

        let id = vm.profiles.first!.id
        try await vm.deleteProfile(id: id)

        #expect(vm.profiles.isEmpty)
    }

    @Test @MainActor func updateProfileReflectsChanges() async throws {
        let (vm, _) = try makeViewModelWithStore()

        try await vm.addProfile(
            host: "old.example.com",
            port: 22,
            username: "admin",
            authMethod: .password,
            password: nil,
            autoReconnect: false
        )

        var profile = vm.profiles.first!
        profile.host = "new.example.com"
        profile.username = "root"
        try await vm.updateProfile(profile, password: nil)

        #expect(vm.profiles.first?.host == "new.example.com")
        #expect(vm.profiles.first?.username == "root")
    }

    @Test @MainActor func addProfileWithInvalidHostThrows() async throws {
        let (vm, _) = try makeViewModelWithStore()

        await #expect(throws: ConnectionViewModelError.self) {
            try await vm.addProfile(
                host: "",
                port: 22,
                username: "admin",
                authMethod: .password,
                password: nil,
                autoReconnect: false
            )
        }
    }

    @Test @MainActor func addProfileWithInvalidUsernameThrows() async throws {
        let (vm, _) = try makeViewModelWithStore()

        await #expect(throws: ConnectionViewModelError.self) {
            try await vm.addProfile(
                host: "example.com",
                port: 22,
                username: "",
                authMethod: .password,
                password: nil,
                autoReconnect: false
            )
        }
    }

    @Test @MainActor func markConnectedUpdatesLastConnected() async throws {
        let (vm, _) = try makeViewModelWithStore()

        try await vm.addProfile(
            host: "example.com",
            port: 22,
            username: "admin",
            authMethod: .password,
            password: nil,
            autoReconnect: false
        )

        let id = vm.profiles.first!.id
        #expect(vm.profiles.first?.lastConnected == nil)

        try await vm.markConnected(id: id)
        #expect(vm.profiles.first?.lastConnected != nil)
    }

    @Test @MainActor func markConnectedNonExistentProfileThrows() async throws {
        let (vm, _) = try makeViewModelWithStore()

        await #expect(throws: ConnectionViewModelError.self) {
            try await vm.markConnected(id: UUID())
        }
    }

    @Test @MainActor func addProfileTrimsWhitespace() async throws {
        let (vm, _) = try makeViewModelWithStore()

        try await vm.addProfile(
            host: "  example.com  ",
            port: 22,
            username: "  admin  ",
            authMethod: .password,
            password: nil,
            autoReconnect: false
        )

        #expect(vm.profiles.first?.host == "example.com")
        #expect(vm.profiles.first?.username == "admin")
    }

    @Test @MainActor func addProfileWithDifferentAuthMethods() async throws {
        let (vm, _) = try makeViewModelWithStore()

        try await vm.addProfile(
            host: "pw.example.com",
            port: 22,
            username: "user",
            authMethod: .password,
            password: "pass",
            autoReconnect: false
        )

        let keyID = UUID()
        try await vm.addProfile(
            host: "key.example.com",
            port: 22,
            username: "user",
            authMethod: .importedKey(keyID: keyID),
            password: nil,
            autoReconnect: false
        )

        try await vm.addProfile(
            host: "se.example.com",
            port: 22,
            username: "user",
            authMethod: .secureEnclaveKey(keyTag: "test-tag"),
            password: nil,
            autoReconnect: true
        )

        #expect(vm.profiles.count == 3)
        let sorted = vm.profiles.sorted { $0.host < $1.host }
        #expect(sorted[0].authMethod == .importedKey(keyID: keyID))
        #expect(sorted[1].authMethod == .password)
        #expect(sorted[2].authMethod == .secureEnclaveKey(keyTag: "test-tag"))
        #expect(sorted[2].autoReconnect == true)
    }

    @MainActor
    private func makeViewModelWithStore() throws -> (ConnectionViewModel, ProfileStore) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try ProfileStore(directory: dir, useBiometricProtection: false)
        let seManager = SecureEnclaveKeyManager()
        let kcManager = try KeychainKeyManager(useBiometricProtection: false)
        let keyManager = KeyManager(secureEnclaveManager: seManager, keychainManager: kcManager)
        let vm = ConnectionViewModel(profileStore: store, keyManager: keyManager)
        return (vm, store)
    }
}

// MARK: - Error Tests

struct ConnectionViewModelErrorTests {
    @Test func errorsAreEquatable() {
        #expect(ConnectionViewModelError.emptyHost == ConnectionViewModelError.emptyHost)
        #expect(ConnectionViewModelError.emptyUsername == ConnectionViewModelError.emptyUsername)
        #expect(ConnectionViewModelError.invalidPort == ConnectionViewModelError.invalidPort)
        #expect(ConnectionViewModelError.emptyHost != ConnectionViewModelError.emptyUsername)
    }

    @Test func hostUnreachableContainsMessage() {
        let error = ConnectionViewModelError.hostUnreachable("timeout")
        if case .hostUnreachable(let msg) = error {
            #expect(msg == "timeout")
        } else {
            Issue.record("Expected hostUnreachable")
        }
    }
}
