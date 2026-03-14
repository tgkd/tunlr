import XCTest
@testable import DivineMarssh

final class ProfileStoreTests: XCTestCase {

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

    private func makeStore() throws -> ProfileStore {
        try ProfileStore(directory: tempDir, useBiometricProtection: false)
    }

    private func makeProfile(
        host: String = "test.host",
        username: String = "user",
        authMethod: SSHAuthMethod = .password
    ) -> SSHConnectionProfile {
        SSHConnectionProfile(host: host, username: username, authMethod: authMethod)
    }

    // MARK: - Create

    func testAddProfile() async throws {
        let store = try makeStore()
        let profile = makeProfile()

        try await store.addProfile(profile)
        let all = await store.allProfiles()

        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.host, "test.host")
    }

    func testAddMultipleProfiles() async throws {
        let store = try makeStore()

        try await store.addProfile(makeProfile(host: "host1"))
        try await store.addProfile(makeProfile(host: "host2"))
        try await store.addProfile(makeProfile(host: "host3"))

        let all = await store.allProfiles()
        XCTAssertEqual(all.count, 3)
    }

    // MARK: - Read

    func testProfileByID() async throws {
        let store = try makeStore()
        let profile = makeProfile()

        try await store.addProfile(profile)
        let fetched = await store.profile(id: profile.id)

        XCTAssertEqual(fetched, profile)
    }

    func testProfileByIDNotFound() async throws {
        let store = try makeStore()
        let fetched = await store.profile(id: UUID())
        XCTAssertNil(fetched)
    }

    // MARK: - Update

    func testUpdateProfile() async throws {
        let store = try makeStore()
        var profile = makeProfile()

        try await store.addProfile(profile)
        profile.host = "updated.host"
        try await store.updateProfile(profile)

        let fetched = await store.profile(id: profile.id)
        XCTAssertEqual(fetched?.host, "updated.host")
    }

    func testUpdateNonexistentProfileThrows() async throws {
        let store = try makeStore()
        let profile = makeProfile()

        do {
            try await store.updateProfile(profile)
            XCTFail("Expected ProfileStoreError.profileNotFound")
        } catch let error as ProfileStoreError {
            XCTAssertEqual(error, .profileNotFound)
        }
    }

    // MARK: - Delete

    func testDeleteProfile() async throws {
        let store = try makeStore()
        let profile = makeProfile()

        try await store.addProfile(profile)
        try await store.deleteProfile(id: profile.id)

        let all = await store.allProfiles()
        XCTAssertTrue(all.isEmpty)
    }

    func testDeleteNonexistentProfileIsNoOp() async throws {
        let store = try makeStore()
        try await store.deleteProfile(id: UUID())
        let all = await store.allProfiles()
        XCTAssertTrue(all.isEmpty)
    }

    // MARK: - Persistence across store instances

    func testPersistenceAcrossInstances() async throws {
        let store1 = try makeStore()
        let profile = makeProfile(host: "persistent.host")
        try await store1.addProfile(profile)

        let store2 = try ProfileStore(directory: tempDir, useBiometricProtection: false)
        let all = await store2.allProfiles()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.host, "persistent.host")
    }

    // MARK: - Password storage (Keychain)

    func testPasswordStoredInKeychainNotJSON() async throws {
        let store = try makeStore()
        let profile = makeProfile(authMethod: .password)

        try await store.addProfile(profile, password: "secret123")

        let jsonData = try Data(contentsOf: tempDir.appendingPathComponent("profiles.json"))
        let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
        XCTAssertFalse(jsonString.contains("secret123"), "Password must not appear in JSON file")
    }

    func testPasswordRetrievedFromKeychain() async throws {
        let store = try makeStore()
        let profile = makeProfile(authMethod: .password)

        try await store.addProfile(profile, password: "mypass")
        let retrieved = await store.password(for: profile.id)

        XCTAssertEqual(retrieved, "mypass")
    }

    func testPasswordDeletedWithProfile() async throws {
        let store = try makeStore()
        let profile = makeProfile(authMethod: .password)

        try await store.addProfile(profile, password: "toDelete")
        try await store.deleteProfile(id: profile.id)

        let retrieved = await store.password(for: profile.id)
        XCTAssertNil(retrieved)
    }

    func testPasswordUpdated() async throws {
        let store = try makeStore()
        let profile = makeProfile(authMethod: .password)

        try await store.addProfile(profile, password: "old")
        try await store.updateProfile(profile, password: "new")

        let retrieved = await store.password(for: profile.id)
        XCTAssertEqual(retrieved, "new")
    }

    // MARK: - Backup Exclusion

    func testProfilesFileExcludedFromBackup() async throws {
        let store = try makeStore()
        let profile = makeProfile()
        try await store.addProfile(profile)

        let fileURL = tempDir.appendingPathComponent("profiles.json")
        let resourceValues = try fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertTrue(resourceValues.isExcludedFromBackup == true)
    }

    func testNoPasswordForNonPasswordAuth() async throws {
        let store = try makeStore()
        let profile = makeProfile(authMethod: .secureEnclaveKey(keyTag: "tag"))

        try await store.addProfile(profile, password: "should-not-store")
        let retrieved = await store.password(for: profile.id)
        XCTAssertNil(retrieved)
    }
}
