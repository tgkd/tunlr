import Foundation
import Network
import UIKit

enum SessionManagerState: Sendable, Equatable {
    case idle
    case active(profileID: UUID)
    case backgrounded(profileID: UUID)
    case reconnecting(profileID: UUID)
}

protocol ScenePhaseProviding: Sendable {
    func scenePhaseStream() -> AsyncStream<ScenePhaseValue>
}

enum ScenePhaseValue: Sendable, Equatable {
    case active
    case inactive
    case background
}

protocol NetworkPathProviding: Sendable {
    func currentPathSatisfied() async -> Bool
}

@MainActor
protocol BackgroundTaskProviding: Sendable {
    func beginBackgroundTask(name: String, expirationHandler: (@Sendable () -> Void)?) -> UIBackgroundTaskIdentifier
    func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier)
}

@MainActor
final class SSHSessionManager: ObservableObject, Sendable {
    @Published private(set) var state: SessionManagerState = .idle
    @Published private(set) var activeSession: SSHSession?
    @Published private(set) var activeProfile: SSHConnectionProfile?
    @Published private(set) var restoredProfileID: UUID?

    private let connectionHandlerFactory: @Sendable () -> any SSHConnectionHandling
    private let profileStore: ProfileStore
    private let terminalStateCache: TerminalStateCache?
    private let scenePhaseProvider: any ScenePhaseProviding
    private let networkPathProvider: any NetworkPathProviding
    private let backgroundTaskProvider: any BackgroundTaskProviding

    private var scenePhaseTask: Task<Void, Never>?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    init(
        connectionHandlerFactory: @escaping @Sendable () -> any SSHConnectionHandling,
        profileStore: ProfileStore,
        terminalStateCache: TerminalStateCache? = nil,
        scenePhaseProvider: any ScenePhaseProviding = DefaultScenePhaseProvider(),
        networkPathProvider: any NetworkPathProviding = DefaultNetworkPathProvider(),
        backgroundTaskProvider: any BackgroundTaskProviding = DefaultBackgroundTaskProvider()
    ) {
        self.connectionHandlerFactory = connectionHandlerFactory
        self.profileStore = profileStore
        self.terminalStateCache = terminalStateCache
        self.scenePhaseProvider = scenePhaseProvider
        self.networkPathProvider = networkPathProvider
        self.backgroundTaskProvider = backgroundTaskProvider
    }

    func startSession(for profile: SSHConnectionProfile) async throws {
        await cleanupCurrentSession()

        let session = SSHSession(connectionHandler: connectionHandlerFactory())
        activeSession = session
        activeProfile = profile
        state = .active(profileID: profile.id)

        try await session.connect(profile: profile)

        startScenePhaseObservation()
    }

    func disconnect() async {
        await cleanupCurrentSession()
        await markExplicitQuit()
        state = .idle
        activeSession = nil
        activeProfile = nil
    }

    func checkForRestoredSession() async {
        guard let cache = terminalStateCache else { return }
        guard let cached = await cache.load() else { return }
        guard !cached.wasExplicitQuit else {
            await cache.clear()
            return
        }
        restoredProfileID = cached.profileID
    }

    func clearRestoredSession() async {
        restoredProfileID = nil
        await terminalStateCache?.clear()
    }

    func handleScenePhaseChange(_ phase: ScenePhaseValue) async {
        switch phase {
        case .background:
            await handleEnteredBackground()
        case .active:
            await handleEnteredForeground()
        case .inactive:
            break
        }
    }

    // MARK: - Background Handling

    private func handleEnteredBackground() async {
        guard let profile = activeProfile, let session = activeSession else { return }

        let taskID = backgroundTaskProvider.beginBackgroundTask(
            name: "ssh-disconnect"
        ) { [weak self] in
            Task { @MainActor [weak self] in
                self?.endBackgroundTaskIfNeeded()
            }
        }
        backgroundTaskID = taskID

        state = .backgrounded(profileID: profile.id)

        await saveTerminalState(profileID: profile.id, session: session, wasExplicitQuit: false)

        await session.disconnect()

        endBackgroundTaskIfNeeded()
    }

    private func handleEnteredForeground() async {
        guard case .backgrounded(let profileID) = state else { return }
        guard let profile = activeProfile, profile.id == profileID else { return }

        guard profile.autoReconnect else {
            state = .idle
            activeSession = nil
            activeProfile = nil
            return
        }

        let hasNetwork = await networkPathProvider.currentPathSatisfied()
        guard hasNetwork else {
            state = .idle
            activeSession = nil
            activeProfile = nil
            return
        }

        state = .reconnecting(profileID: profileID)

        do {
            let session = SSHSession(connectionHandler: connectionHandlerFactory())
            activeSession = session
            try await session.connect(profile: profile)
            state = .active(profileID: profileID)
        } catch {
            state = .idle
            activeSession = nil
            activeProfile = nil
        }
    }

    // MARK: - Private

    private func cleanupCurrentSession() async {
        scenePhaseTask?.cancel()
        scenePhaseTask = nil
        if let session = activeSession {
            await session.disconnect()
        }
        endBackgroundTaskIfNeeded()
    }

    private func endBackgroundTaskIfNeeded() {
        if backgroundTaskID != .invalid {
            backgroundTaskProvider.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }

    private func startScenePhaseObservation() {
        scenePhaseTask?.cancel()
        let provider = scenePhaseProvider
        scenePhaseTask = Task { [weak self] in
            for await phase in provider.scenePhaseStream() {
                guard !Task.isCancelled else { return }
                await self?.handleScenePhaseChange(phase)
            }
        }
    }

    private func saveTerminalState(profileID: UUID, session: SSHSession, wasExplicitQuit: Bool) async {
        guard let cache = terminalStateCache else { return }
        let pty = await session.ptyConfiguration
        let state = CachedTerminalState(
            profileID: profileID,
            ptyConfiguration: CachedTerminalState.CachedPTYConfiguration(
                cols: pty.cols,
                rows: pty.rows,
                term: pty.term
            ),
            terminalTitle: "",
            cursorRow: 0,
            cursorCol: 0,
            scrollbackLineCount: 0,
            screenContent: [],
            timestamp: Date(),
            wasExplicitQuit: wasExplicitQuit
        )
        try? await cache.save(state)
    }

    private func markExplicitQuit() async {
        guard let cache = terminalStateCache, let profile = activeProfile else { return }
        let state = CachedTerminalState(
            profileID: profile.id,
            ptyConfiguration: CachedTerminalState.CachedPTYConfiguration(cols: 80, rows: 24),
            terminalTitle: "",
            cursorRow: 0,
            cursorCol: 0,
            scrollbackLineCount: 0,
            screenContent: [],
            timestamp: Date(),
            wasExplicitQuit: true
        )
        try? await cache.save(state)
    }
}

// MARK: - Default Providers

final class DefaultScenePhaseProvider: ScenePhaseProviding {
    func scenePhaseStream() -> AsyncStream<ScenePhaseValue> {
        AsyncStream { continuation in
            let center = NotificationCenter.default

            let foregroundTask = Task { @MainActor in
                for await _ in center.notifications(named: UIApplication.willEnterForegroundNotification) {
                    continuation.yield(.active)
                }
            }

            let backgroundTask = Task { @MainActor in
                for await _ in center.notifications(named: UIApplication.didEnterBackgroundNotification) {
                    continuation.yield(.background)
                }
            }

            continuation.onTermination = { @Sendable _ in
                foregroundTask.cancel()
                backgroundTask.cancel()
            }
        }
    }
}

final class DefaultNetworkPathProvider: NetworkPathProviding {
    func currentPathSatisfied() async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "com.divinemarssh.networkcheck")
            monitor.pathUpdateHandler = { path in
                monitor.cancel()
                continuation.resume(returning: path.status == .satisfied)
            }
            monitor.start(queue: queue)
        }
    }
}

final class DefaultBackgroundTaskProvider: BackgroundTaskProviding {
    func beginBackgroundTask(name: String, expirationHandler: (@Sendable () -> Void)?) -> UIBackgroundTaskIdentifier {
        UIApplication.shared.beginBackgroundTask(withName: name) {
            expirationHandler?()
        }
    }

    func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier) {
        UIApplication.shared.endBackgroundTask(identifier)
    }
}
