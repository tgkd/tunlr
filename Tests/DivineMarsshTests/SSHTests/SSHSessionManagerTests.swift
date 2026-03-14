import Testing
import Foundation
import UIKit
@testable import DivineMarssh

// MARK: - Mock Providers

final class MockScenePhaseProvider: ScenePhaseProviding, @unchecked Sendable {
    private var continuation: AsyncStream<ScenePhaseValue>.Continuation?

    func scenePhaseStream() -> AsyncStream<ScenePhaseValue> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    func send(_ phase: ScenePhaseValue) {
        continuation?.yield(phase)
    }

    func finish() {
        continuation?.finish()
    }
}

final class MockNetworkPathProvider: NetworkPathProviding, @unchecked Sendable {
    var isSatisfied: Bool = true

    func currentPathSatisfied() async -> Bool {
        isSatisfied
    }
}

final class MockBackgroundTaskProvider: BackgroundTaskProviding, @unchecked Sendable {
    var beginCalled = false
    var endCalled = false
    var expirationHandler: (@Sendable () -> Void)?

    func beginBackgroundTask(name: String, expirationHandler: (@Sendable () -> Void)?) -> UIBackgroundTaskIdentifier {
        beginCalled = true
        self.expirationHandler = expirationHandler
        return UIBackgroundTaskIdentifier(rawValue: 42)
    }

    func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier) {
        endCalled = true
    }
}

// MARK: - State Tests

struct SSHSessionManagerStateTests {
    private func makeTestProfile(autoReconnect: Bool = false) -> SSHConnectionProfile {
        SSHConnectionProfile(
            host: "test.example.com",
            port: 22,
            username: "testuser",
            authMethod: .password,
            autoReconnect: autoReconnect
        )
    }

    @MainActor
    private func makeManager(
        client: MockSSHClient? = nil,
        shouldFail: Bool = false,
        networkSatisfied: Bool = true,
        scenePhaseProvider: MockScenePhaseProvider? = nil,
        backgroundTaskProvider: MockBackgroundTaskProvider? = nil
    ) throws -> (SSHSessionManager, MockScenePhaseProvider, MockNetworkPathProvider, MockBackgroundTaskProvider) {
        let mockClient = client ?? MockSSHClient()
        let handler = MockConnectionHandler(client: mockClient, shouldFail: shouldFail)
        let store = try ProfileStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let sceneProvider = scenePhaseProvider ?? MockScenePhaseProvider()
        let networkProvider = MockNetworkPathProvider()
        networkProvider.isSatisfied = networkSatisfied
        let bgProvider = backgroundTaskProvider ?? MockBackgroundTaskProvider()

        let manager = SSHSessionManager(
            connectionHandlerFactory: { handler },
            profileStore: store,
            scenePhaseProvider: sceneProvider,
            networkPathProvider: networkProvider,
            backgroundTaskProvider: bgProvider
        )

        return (manager, sceneProvider, networkProvider, bgProvider)
    }

    @Test @MainActor func initialStateIsIdle() throws {
        let (manager, _, _, _) = try makeManager()
        #expect(manager.state == .idle)
        #expect(manager.activeSession == nil)
        #expect(manager.activeProfile == nil)
    }

    @Test @MainActor func startSessionSetsActive() async throws {
        let (manager, _, _, _) = try makeManager()
        let profile = makeTestProfile()

        try await manager.startSession(for: profile)

        #expect(manager.state == .active(profileID: profile.id))
        #expect(manager.activeSession != nil)
        #expect(manager.activeProfile?.id == profile.id)
    }

    @Test @MainActor func disconnectResetsToIdle() async throws {
        let (manager, _, _, _) = try makeManager()
        let profile = makeTestProfile()

        try await manager.startSession(for: profile)
        await manager.disconnect()

        #expect(manager.state == .idle)
        #expect(manager.activeSession == nil)
        #expect(manager.activeProfile == nil)
    }

    @Test @MainActor func startSessionFailureKeepsIdle() async throws {
        let (manager, _, _, _) = try makeManager(shouldFail: true)
        let profile = makeTestProfile()

        do {
            try await manager.startSession(for: profile)
            Issue.record("Expected error")
        } catch {
            // Expected
        }
    }

    @Test @MainActor func startNewSessionDisconnectsPrevious() async throws {
        let firstClient = MockSSHClient()
        let (manager, _, _, _) = try makeManager(client: firstClient)
        let profile1 = makeTestProfile()
        let profile2 = SSHConnectionProfile(
            host: "other.example.com",
            port: 22,
            username: "otheruser",
            authMethod: .password
        )

        try await manager.startSession(for: profile1)
        try await manager.startSession(for: profile2)

        #expect(firstClient.closeCalled)
        #expect(manager.activeProfile?.host == "other.example.com")
    }
}

// MARK: - Background/Foreground Lifecycle Tests

struct SSHSessionManagerLifecycleTests {
    private func makeTestProfile(autoReconnect: Bool = false) -> SSHConnectionProfile {
        SSHConnectionProfile(
            host: "test.example.com",
            port: 22,
            username: "testuser",
            authMethod: .password,
            autoReconnect: autoReconnect
        )
    }

    @MainActor
    private func makeManager(
        client: MockSSHClient? = nil,
        networkSatisfied: Bool = true
    ) throws -> (SSHSessionManager, MockScenePhaseProvider, MockNetworkPathProvider, MockBackgroundTaskProvider) {
        let mockClient = client ?? MockSSHClient()
        let handler = MockConnectionHandler(client: mockClient)
        let store = try ProfileStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let sceneProvider = MockScenePhaseProvider()
        let networkProvider = MockNetworkPathProvider()
        networkProvider.isSatisfied = networkSatisfied
        let bgProvider = MockBackgroundTaskProvider()

        let manager = SSHSessionManager(
            connectionHandlerFactory: { handler },
            profileStore: store,
            scenePhaseProvider: sceneProvider,
            networkPathProvider: networkProvider,
            backgroundTaskProvider: bgProvider
        )

        return (manager, sceneProvider, networkProvider, bgProvider)
    }

    @Test @MainActor func backgroundDisconnectsAndTransitionsToBackgrounded() async throws {
        let (manager, _, _, bgProvider) = try makeManager()
        let profile = makeTestProfile()

        try await manager.startSession(for: profile)
        await manager.handleScenePhaseChange(.background)

        #expect(manager.state == .backgrounded(profileID: profile.id))
        #expect(bgProvider.beginCalled)
        #expect(bgProvider.endCalled)
    }

    @Test @MainActor func foregroundWithAutoReconnectReconnects() async throws {
        let (manager, _, _, _) = try makeManager()
        let profile = makeTestProfile(autoReconnect: true)

        try await manager.startSession(for: profile)
        await manager.handleScenePhaseChange(.background)

        #expect(manager.state == .backgrounded(profileID: profile.id))

        await manager.handleScenePhaseChange(.active)

        #expect(manager.state == .active(profileID: profile.id))
        #expect(manager.activeSession != nil)
    }

    @Test @MainActor func foregroundWithoutAutoReconnectGoesIdle() async throws {
        let (manager, _, _, _) = try makeManager()
        let profile = makeTestProfile(autoReconnect: false)

        try await manager.startSession(for: profile)
        await manager.handleScenePhaseChange(.background)
        await manager.handleScenePhaseChange(.active)

        #expect(manager.state == .idle)
        #expect(manager.activeSession == nil)
    }

    @Test @MainActor func foregroundWithNoNetworkGoesIdle() async throws {
        let (manager, _, networkProvider, _) = try makeManager()
        let profile = makeTestProfile(autoReconnect: true)

        try await manager.startSession(for: profile)
        await manager.handleScenePhaseChange(.background)

        networkProvider.isSatisfied = false
        await manager.handleScenePhaseChange(.active)

        #expect(manager.state == .idle)
        #expect(manager.activeSession == nil)
    }

    @Test @MainActor func backgroundWhenIdleIsNoOp() async throws {
        let (manager, _, _, bgProvider) = try makeManager()

        await manager.handleScenePhaseChange(.background)

        #expect(manager.state == .idle)
        #expect(!bgProvider.beginCalled)
    }

    @Test @MainActor func foregroundWhenNotBackgroundedIsNoOp() async throws {
        let (manager, _, _, _) = try makeManager()

        await manager.handleScenePhaseChange(.active)

        #expect(manager.state == .idle)
    }

    @Test @MainActor func inactivePhaseIsNoOp() async throws {
        let (manager, _, _, _) = try makeManager()
        let profile = makeTestProfile()

        try await manager.startSession(for: profile)
        await manager.handleScenePhaseChange(.inactive)

        #expect(manager.state == .active(profileID: profile.id))
    }

    @Test @MainActor func backgroundTaskExpirationEndsTask() async throws {
        let bgProvider = MockBackgroundTaskProvider()
        let mockClient = MockSSHClient()
        let handler = MockConnectionHandler(client: mockClient)
        let store = try ProfileStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let sceneProvider = MockScenePhaseProvider()
        let networkProvider = MockNetworkPathProvider()

        let manager = SSHSessionManager(
            connectionHandlerFactory: { handler },
            profileStore: store,
            scenePhaseProvider: sceneProvider,
            networkPathProvider: networkProvider,
            backgroundTaskProvider: bgProvider
        )

        let profile = makeTestProfile()
        try await manager.startSession(for: profile)

        await manager.handleScenePhaseChange(.background)

        #expect(bgProvider.beginCalled)
        #expect(bgProvider.endCalled)
    }
}

// MARK: - SessionManagerState Equatable Tests

struct SessionManagerStateEquatableTests {
    @Test func stateEquality() {
        let id1 = UUID()
        let id2 = UUID()

        #expect(SessionManagerState.idle == SessionManagerState.idle)
        #expect(SessionManagerState.active(profileID: id1) == SessionManagerState.active(profileID: id1))
        #expect(SessionManagerState.active(profileID: id1) != SessionManagerState.active(profileID: id2))
        #expect(SessionManagerState.backgrounded(profileID: id1) == SessionManagerState.backgrounded(profileID: id1))
        #expect(SessionManagerState.reconnecting(profileID: id1) == SessionManagerState.reconnecting(profileID: id1))
        #expect(SessionManagerState.idle != SessionManagerState.active(profileID: id1))
        #expect(SessionManagerState.active(profileID: id1) != SessionManagerState.backgrounded(profileID: id1))
    }
}

// MARK: - ScenePhaseValue Tests

struct ScenePhaseValueTests {
    @Test func phaseEquality() {
        #expect(ScenePhaseValue.active == ScenePhaseValue.active)
        #expect(ScenePhaseValue.inactive == ScenePhaseValue.inactive)
        #expect(ScenePhaseValue.background == ScenePhaseValue.background)
        #expect(ScenePhaseValue.active != ScenePhaseValue.background)
        #expect(ScenePhaseValue.active != ScenePhaseValue.inactive)
    }
}
