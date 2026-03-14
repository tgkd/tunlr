import Testing
import Foundation
@testable import DivineMarssh

// MARK: - Integration: SSH Connection Lifecycle

struct SSHConnectionIntegrationTests {

    private func makeTestProfile(authMethod: SSHAuthMethod = .password) -> SSHConnectionProfile {
        SSHConnectionProfile(
            host: "test.example.com",
            port: 22,
            username: "testuser",
            authMethod: authMethod
        )
    }

    // MARK: - Connect, Authenticate, Run Command, Disconnect

    @Test func fullConnectionLifecycle() async throws {
        let mockClient = MockSSHClient()
        let handler = MockConnectionHandler(client: mockClient)
        let session = SSHSession(connectionHandler: handler)

        let state1 = await session.connectionState
        #expect(state1 == .disconnected)

        try await session.connect(profile: makeTestProfile())

        let state2 = await session.connectionState
        #expect(state2 == .connected)

        await session.requestPTY(cols: 80, rows: 24, term: "xterm-256color")
        let stream = try await session.openShellChannel()

        #expect(mockClient.shellOpened)
        #expect(mockClient.lastPTY?.cols == 80)
        #expect(mockClient.lastPTY?.rows == 24)
        #expect(mockClient.lastPTY?.term == "xterm-256color")

        let commandData = Data("echo hello\n".utf8)
        try await session.write(commandData)

        _ = stream

        await session.disconnect()

        let state3 = await session.connectionState
        #expect(state3 == .disconnected)
        #expect(mockClient.closeCalled)
    }

    @Test func connectAuthenticateWithEd25519Key() async throws {
        let mockClient = MockSSHClient()
        let handler = MockConnectionHandler(client: mockClient)
        let session = SSHSession(connectionHandler: handler)

        let profile = makeTestProfile(authMethod: .importedKey(keyID: UUID()))
        try await session.connect(profile: profile)

        let state = await session.connectionState
        #expect(state == .connected)
        #expect(mockClient.isConnected)
    }

    @Test func connectAuthenticateWithSecureEnclaveKey() async throws {
        let mockClient = MockSSHClient()
        let handler = MockConnectionHandler(client: mockClient)
        let session = SSHSession(connectionHandler: handler)

        let profile = makeTestProfile(authMethod: .secureEnclaveKey(keyTag: "se-test-key"))
        try await session.connect(profile: profile)

        let state = await session.connectionState
        #expect(state == .connected)
    }

    @Test func shellDataFlowThroughChannel() async throws {
        let mockClient = MockSSHClient()
        let handler = MockConnectionHandler(client: mockClient)
        let session = SSHSession(connectionHandler: handler)

        try await session.connect(profile: makeTestProfile())
        await session.requestPTY(cols: 120, rows: 40)

        let stream = try await session.openShellChannel()

        try await session.write(Data("ls -la\n".utf8))

        let pty = await session.ptyConfiguration
        #expect(pty.cols == 120)
        #expect(pty.rows == 40)

        _ = stream
    }

    @Test func windowResizeDuringSession() async throws {
        let mockClient = MockSSHClient()
        let handler = MockConnectionHandler(client: mockClient)
        let session = SSHSession(connectionHandler: handler)

        try await session.connect(profile: makeTestProfile())
        _ = try await session.openShellChannel()

        try await session.sendWindowChange(cols: 200, rows: 60)

        let pty = await session.ptyConfiguration
        #expect(pty.cols == 200)
        #expect(pty.rows == 60)
    }

    @Test func multipleCommandsInSession() async throws {
        let mockClient = MockSSHClient()
        let handler = MockConnectionHandler(client: mockClient)
        let session = SSHSession(connectionHandler: handler)

        try await session.connect(profile: makeTestProfile())
        _ = try await session.openShellChannel()

        try await session.write(Data("whoami\n".utf8))
        try await session.write(Data("pwd\n".utf8))
        try await session.write(Data("ls\n".utf8))

        await session.disconnect()
        let state = await session.connectionState
        #expect(state == .disconnected)
    }

    // MARK: - Error Handling

    @Test func connectionFailureDoesNotLeavePartialState() async {
        let handler = MockConnectionHandler(error: SSHSessionError.authenticationFailed)
        let session = SSHSession(connectionHandler: handler)

        do {
            try await session.connect(profile: makeTestProfile())
            Issue.record("Expected error")
        } catch {
            let sessionError = error as? SSHSessionError
            #expect(sessionError == .authenticationFailed)
        }

        let state = await session.connectionState
        #expect(state == .disconnected)
    }

    @Test func writeWithoutShellFails() async throws {
        let mockClient = MockSSHClient()
        let handler = MockConnectionHandler(client: mockClient)
        let session = SSHSession(connectionHandler: handler)

        try await session.connect(profile: makeTestProfile())

        await #expect(throws: SSHSessionError.self) {
            try await session.write(Data("test".utf8))
        }
    }

    @Test func openShellWithoutConnectionFails() async {
        let session = SSHSession(connectionHandler: MockConnectionHandler(client: MockSSHClient()))

        await #expect(throws: SSHSessionError.self) {
            _ = try await session.openShellChannel()
        }
    }

    @Test func doubleConnectFails() async throws {
        let mockClient = MockSSHClient()
        let handler = MockConnectionHandler(client: mockClient)
        let session = SSHSession(connectionHandler: handler)

        try await session.connect(profile: makeTestProfile())

        await #expect(throws: SSHSessionError.self) {
            try await session.connect(profile: makeTestProfile())
        }
    }

    @Test func reconnectAfterDisconnect() async throws {
        let mockClient = MockSSHClient()
        let handler = MockConnectionHandler(client: mockClient)
        let session = SSHSession(connectionHandler: handler)

        try await session.connect(profile: makeTestProfile())
        await session.disconnect()

        let newSession = SSHSession(connectionHandler: handler)
        try await newSession.connect(profile: makeTestProfile())

        let state = await newSession.connectionState
        #expect(state == .connected)
    }
}

// MARK: - Integration: Profile Store + Session

struct ProfileStoreSessionIntegrationTests {

    @Test func sessionUsesProfileFromStore() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try ProfileStore(directory: dir)

        let profile = SSHConnectionProfile(
            host: "integration-test.example.com",
            port: 2222,
            username: "integrationuser",
            authMethod: .password
        )
        try await store.addProfile(profile)

        let loaded = await store.allProfiles()
        let loadedProfile = loaded.first { $0.id == profile.id }
        #expect(loadedProfile != nil)
        #expect(loadedProfile?.host == "integration-test.example.com")
        #expect(loadedProfile?.port == 2222)

        let mockClient = MockSSHClient()
        let handler = MockConnectionHandler(client: mockClient)
        let session = SSHSession(connectionHandler: handler)

        try await session.connect(profile: loadedProfile!)

        let state = await session.connectionState
        #expect(state == .connected)

        await session.disconnect()
        try await store.deleteProfile(id: profile.id)
    }

    @Test func profileCRUDIntegration() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try ProfileStore(directory: dir)

        let profile1 = SSHConnectionProfile(host: "host1.example.com", username: "user1", authMethod: .password)
        let profile2 = SSHConnectionProfile(host: "host2.example.com", port: 2222, username: "user2", authMethod: .importedKey(keyID: UUID()))

        try await store.addProfile(profile1)
        try await store.addProfile(profile2)

        var profiles = await store.allProfiles()
        #expect(profiles.count == 2)

        var updated = profile1
        updated.host = "updated.example.com"
        try await store.updateProfile(updated)

        profiles = await store.allProfiles()
        let updatedProfile = profiles.first { $0.id == profile1.id }
        #expect(updatedProfile?.host == "updated.example.com")

        try await store.deleteProfile(id: profile2.id)
        profiles = await store.allProfiles()
        #expect(profiles.count == 1)
        #expect(profiles.first?.id == profile1.id)
    }
}
