import Testing
import Foundation
import UIKit
@testable import DivineMarssh

private final class AtomicCounter: @unchecked Sendable {
    private var _value: Int = 0
    var value: Int { _value }
    func increment() -> Int {
        let current = _value
        _value += 1
        return current
    }
}

// MARK: - Integration: Background/Foreground Reconnection

struct ReconnectionIntegrationTests {

    private func makeTestProfile(autoReconnect: Bool = true) -> SSHConnectionProfile {
        SSHConnectionProfile(
            host: "reconnect.example.com",
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
        terminalStateCache: TerminalStateCache? = nil
    ) throws -> (
        SSHSessionManager,
        MockScenePhaseProvider,
        MockNetworkPathProvider,
        MockBackgroundTaskProvider
    ) {
        let mockClient = client ?? MockSSHClient()
        let handler = MockConnectionHandler(client: mockClient, shouldFail: shouldFail)
        let store = try ProfileStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let sceneProvider = MockScenePhaseProvider()
        let networkProvider = MockNetworkPathProvider()
        networkProvider.isSatisfied = networkSatisfied
        let bgProvider = MockBackgroundTaskProvider()

        let manager = SSHSessionManager(
            connectionHandlerFactory: { handler },
            profileStore: store,
            terminalStateCache: terminalStateCache,
            scenePhaseProvider: sceneProvider,
            networkPathProvider: networkProvider,
            backgroundTaskProvider: bgProvider
        )

        return (manager, sceneProvider, networkProvider, bgProvider)
    }

    // MARK: - Full Background/Foreground Cycle

    @Test @MainActor func fullBackgroundForegroundCycleWithAutoReconnect() async throws {
        let (manager, _, _, bgProvider) = try makeManager()
        let profile = makeTestProfile(autoReconnect: true)

        try await manager.startSession(for: profile)
        #expect(manager.state == .active(profileID: profile.id))
        #expect(manager.activeSession != nil)

        await manager.handleScenePhaseChange(.background)
        #expect(manager.state == .backgrounded(profileID: profile.id))
        #expect(bgProvider.beginCalled)
        #expect(bgProvider.endCalled)

        await manager.handleScenePhaseChange(.active)
        #expect(manager.state == .active(profileID: profile.id))
        #expect(manager.activeSession != nil)
    }

    @Test @MainActor func fullBackgroundForegroundCycleWithoutAutoReconnect() async throws {
        let (manager, _, _, _) = try makeManager()
        let profile = makeTestProfile(autoReconnect: false)

        try await manager.startSession(for: profile)
        #expect(manager.state == .active(profileID: profile.id))

        await manager.handleScenePhaseChange(.background)
        #expect(manager.state == .backgrounded(profileID: profile.id))

        await manager.handleScenePhaseChange(.active)
        #expect(manager.state == .idle)
        #expect(manager.activeSession == nil)
        #expect(manager.activeProfile == nil)
    }

    // MARK: - State Restoration

    @Test @MainActor func stateRestorationSavesOnBackground() async throws {
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = try TerminalStateCache(directory: cacheDir)
        let (manager, _, _, _) = try makeManager(terminalStateCache: cache)
        let profile = makeTestProfile()

        try await manager.startSession(for: profile)
        await manager.handleScenePhaseChange(.background)

        let cached = await cache.load()
        #expect(cached != nil)
        #expect(cached?.profileID == profile.id)
        #expect(cached?.wasExplicitQuit == false)
    }

    @Test @MainActor func explicitDisconnectMarksQuit() async throws {
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = try TerminalStateCache(directory: cacheDir)
        let (manager, _, _, _) = try makeManager(terminalStateCache: cache)
        let profile = makeTestProfile()

        try await manager.startSession(for: profile)
        await manager.disconnect()

        let cached = await cache.load()
        #expect(cached != nil)
        #expect(cached?.wasExplicitQuit == true)
    }

    @Test @MainActor func restoreSessionAfterInterruption() async throws {
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = try TerminalStateCache(directory: cacheDir)

        let profileID = UUID()
        let state = CachedTerminalState(
            profileID: profileID,
            ptyConfiguration: CachedTerminalState.CachedPTYConfiguration(cols: 80, rows: 24),
            terminalTitle: "test-session",
            cursorRow: 5,
            cursorCol: 10,
            scrollbackLineCount: 100,
            screenContent: ["line1", "line2"],
            timestamp: Date(),
            wasExplicitQuit: false
        )
        try await cache.save(state)

        let (manager, _, _, _) = try makeManager(terminalStateCache: cache)

        await manager.checkForRestoredSession()
        #expect(manager.restoredProfileID == profileID)
    }

    @Test @MainActor func noRestoreAfterExplicitQuit() async throws {
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = try TerminalStateCache(directory: cacheDir)

        let state = CachedTerminalState(
            profileID: UUID(),
            ptyConfiguration: CachedTerminalState.CachedPTYConfiguration(cols: 80, rows: 24),
            terminalTitle: "",
            cursorRow: 0,
            cursorCol: 0,
            scrollbackLineCount: 0,
            screenContent: [],
            timestamp: Date(),
            wasExplicitQuit: true
        )
        try await cache.save(state)

        let (manager, _, _, _) = try makeManager(terminalStateCache: cache)

        await manager.checkForRestoredSession()
        #expect(manager.restoredProfileID == nil)
    }

    @Test @MainActor func clearRestoredSession() async throws {
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = try TerminalStateCache(directory: cacheDir)

        let state = CachedTerminalState(
            profileID: UUID(),
            ptyConfiguration: CachedTerminalState.CachedPTYConfiguration(cols: 80, rows: 24),
            terminalTitle: "",
            cursorRow: 0,
            cursorCol: 0,
            scrollbackLineCount: 0,
            screenContent: [],
            timestamp: Date(),
            wasExplicitQuit: false
        )
        try await cache.save(state)

        let (manager, _, _, _) = try makeManager(terminalStateCache: cache)

        await manager.checkForRestoredSession()
        #expect(manager.restoredProfileID != nil)

        await manager.clearRestoredSession()
        #expect(manager.restoredProfileID == nil)

        let cached = await cache.load()
        #expect(cached == nil)
    }

    // MARK: - Network Failure During Reconnect

    @Test @MainActor func reconnectFailsWithNoNetwork() async throws {
        let (manager, _, networkProvider, _) = try makeManager()
        let profile = makeTestProfile(autoReconnect: true)

        try await manager.startSession(for: profile)
        await manager.handleScenePhaseChange(.background)

        networkProvider.isSatisfied = false
        await manager.handleScenePhaseChange(.active)

        #expect(manager.state == .idle)
        #expect(manager.activeSession == nil)
    }

    @Test @MainActor func reconnectFailsWithConnectionError() async throws {
        let mockClient = MockSSHClient()
        let successHandler = MockConnectionHandler(client: mockClient)
        let failHandler = MockConnectionHandler(error: SSHSessionError.authenticationFailed)

        let store = try ProfileStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let sceneProvider = MockScenePhaseProvider()
        let networkProvider = MockNetworkPathProvider()
        let bgProvider = MockBackgroundTaskProvider()

        let attemptCounter = AtomicCounter()
        let manager = SSHSessionManager(
            connectionHandlerFactory: { [successHandler, failHandler] in
                let count = attemptCounter.increment()
                return count == 0 ? successHandler : failHandler
            },
            profileStore: store,
            scenePhaseProvider: sceneProvider,
            networkPathProvider: networkProvider,
            backgroundTaskProvider: bgProvider
        )

        let profile = makeTestProfile(autoReconnect: true)
        try await manager.startSession(for: profile)

        await manager.handleScenePhaseChange(.background)
        await manager.handleScenePhaseChange(.active)

        #expect(manager.state == .idle)
    }

    // MARK: - Multiple Background/Foreground Cycles

    @Test @MainActor func multipleBackgroundForegroundCycles() async throws {
        let (manager, _, _, _) = try makeManager()
        let profile = makeTestProfile(autoReconnect: true)

        try await manager.startSession(for: profile)

        for _ in 0..<3 {
            #expect(manager.state == .active(profileID: profile.id))

            await manager.handleScenePhaseChange(.background)
            #expect(manager.state == .backgrounded(profileID: profile.id))

            await manager.handleScenePhaseChange(.active)
        }

        #expect(manager.state == .active(profileID: profile.id))
        #expect(manager.activeSession != nil)
    }

    // MARK: - Inactive Phase Handling

    @Test @MainActor func inactivePhaseDoesNotAffectSession() async throws {
        let (manager, _, _, _) = try makeManager()
        let profile = makeTestProfile()

        try await manager.startSession(for: profile)
        let sessionBefore = manager.activeSession

        await manager.handleScenePhaseChange(.inactive)

        #expect(manager.state == .active(profileID: profile.id))
        #expect(manager.activeSession != nil)
        _ = sessionBefore
    }

    // MARK: - State Cache PTY Preservation

    @Test @MainActor func backgroundPreservesPTYConfig() async throws {
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = try TerminalStateCache(directory: cacheDir)
        let (manager, _, _, _) = try makeManager(terminalStateCache: cache)
        let profile = makeTestProfile()

        try await manager.startSession(for: profile)

        if let session = manager.activeSession {
            await session.requestPTY(cols: 132, rows: 43, term: "xterm-256color")
        }

        await manager.handleScenePhaseChange(.background)

        let cached = await cache.load()
        #expect(cached != nil)
        #expect(cached?.ptyConfiguration.cols == 132)
        #expect(cached?.ptyConfiguration.rows == 43)
        #expect(cached?.ptyConfiguration.term == "xterm-256color")
    }
}
