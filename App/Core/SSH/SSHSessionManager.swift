import Foundation
import Network
import UIKit

enum SSHSessionManagerError: Error, Equatable {
    case superseded
    case noPendingSession
    case remoteSessionCreateUnsupported(SessionBackendKind)
    case remoteSessionCreateFailed(String)
    case remoteSessionNotFound(String)
}

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
    @Published private(set) var pendingHostKeyMismatch: PendingHostKeyMismatch?
    @Published private(set) var sessionChoice: RemoteSessionChoice?

    private let connectionHandlerFactory: @Sendable () -> any SSHConnectionHandling
    private let profileStore: ProfileStore
    private let terminalStateCache: TerminalStateCache?
    private let hostKeyVerifier: HostKeyVerifier?
    private let scenePhaseProvider: any ScenePhaseProviding
    private let networkPathProvider: any NetworkPathProviding
    private let backgroundTaskProvider: any BackgroundTaskProviding
    private let sessionDiscovery: @Sendable (any RemoteCommandRunning) async -> [RemoteSessionEntry]
    private let sessionBackends: [any RemoteSessionBackend]

    private var scenePhaseTask: Task<Void, Never>?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var connectionGeneration: Int = 0
    private var restoredPTY: (profileID: UUID, configuration: PTYConfiguration)?
    private var pendingAttach: PendingAttach?
    private var reconnectTarget: AttachTarget?

    private struct PendingAttach {
        let session: SSHSession
        let profileID: UUID
        let generation: Int
    }

    private struct AttachTarget: Equatable {
        let backend: SessionBackendKind
        let name: String
    }

    private enum AttachResolution {
        case attach(RemoteSessionEntry?)
        case choose(entries: [RemoteSessionEntry], missingName: String?)
    }

    init(
        connectionHandlerFactory: @escaping @Sendable () -> any SSHConnectionHandling,
        profileStore: ProfileStore,
        terminalStateCache: TerminalStateCache? = nil,
        hostKeyVerifier: HostKeyVerifier? = nil,
        scenePhaseProvider: any ScenePhaseProviding = DefaultScenePhaseProvider(),
        networkPathProvider: any NetworkPathProviding = DefaultNetworkPathProvider(),
        backgroundTaskProvider: any BackgroundTaskProviding = DefaultBackgroundTaskProvider(),
        sessionDiscovery: @escaping @Sendable (any RemoteCommandRunning) async -> [RemoteSessionEntry] = {
            await RemoteSessionDiscovery().discover(using: $0)
        },
        sessionBackends: [any RemoteSessionBackend] = RemoteSessionBackends.all
    ) {
        self.connectionHandlerFactory = connectionHandlerFactory
        self.profileStore = profileStore
        self.terminalStateCache = terminalStateCache
        self.hostKeyVerifier = hostKeyVerifier
        self.scenePhaseProvider = scenePhaseProvider
        self.networkPathProvider = networkPathProvider
        self.backgroundTaskProvider = backgroundTaskProvider
        self.sessionDiscovery = sessionDiscovery
        self.sessionBackends = sessionBackends
    }

    func startSession(for profile: SSHConnectionProfile) async throws {
        connectionGeneration += 1
        let generation = connectionGeneration

        await cleanupCurrentSession()
        guard generation == connectionGeneration else {
            throw SSHSessionManagerError.superseded
        }

        let session = SSHSession(connectionHandler: connectionHandlerFactory())
        if let restoredPTY, restoredPTY.profileID == profile.id {
            await session.requestPTY(
                cols: restoredPTY.configuration.cols,
                rows: restoredPTY.configuration.rows,
                term: restoredPTY.configuration.term
            )
            self.restoredPTY = nil
        }
        activeProfile = profile

        do {
            try await session.connect(profile: profile)
        } catch {
            let pending = await hostKeyVerifier?.takePendingMismatch(
                hostname: profile.host,
                port: profile.port
            )
            guard generation == connectionGeneration else {
                throw SSHSessionManagerError.superseded
            }
            activeSession = nil
            activeProfile = nil
            state = .idle
            if let pending {
                pendingHostKeyMismatch = pending
            }
            throw error
        }

        guard generation == connectionGeneration else {
            await session.disconnect()
            throw SSHSessionManagerError.superseded
        }

        let resolution = try await resolveAttachment(
            for: profile.sessionAttach,
            session: session,
            generation: generation
        )
        switch resolution {
        case .attach(let entry):
            await session.setShellCommand(entry?.attachCommand)
            try await ensureCurrent(generation, disconnecting: session)
            activate(session: session, profileID: profile.id, entry: entry)
        case .choose(let entries, let missingName):
            hold(
                session: session,
                profileID: profile.id,
                generation: generation,
                entries: entries,
                missingName: missingName
            )
        }
    }

    /// Pin the key the user approved from the mismatch warning. Takes the value
    /// explicitly (captured from the alert) because the published property may
    /// already be cleared by the alert's dismissal by the time this runs. The
    /// caller is responsible for retrying `startSession` afterwards.
    func trust(_ pending: PendingHostKeyMismatch) async throws {
        guard let hostKeyVerifier else { return }
        try await hostKeyVerifier.trust(pending)
        pendingHostKeyMismatch = nil
    }

    func dismissPendingHostKey() {
        pendingHostKeyMismatch = nil
    }

    func chooseRemoteSession(_ entry: RemoteSessionEntry?) async {
        guard let pending = pendingAttach, pending.generation == connectionGeneration else { return }
        pendingAttach = nil

        await pending.session.setShellCommand(entry?.attachCommand)
        guard pending.generation == connectionGeneration else {
            await pending.session.disconnect()
            return
        }
        activate(session: pending.session, profileID: pending.profileID, entry: entry)
    }

    func createRemoteSession(backend: SessionBackendKind, name: String) async throws {
        guard let pending = pendingAttach, pending.generation == connectionGeneration else {
            throw SSHSessionManagerError.noPendingSession
        }
        guard let command = createCommand(for: backend, name: name) else {
            throw SSHSessionManagerError.remoteSessionCreateUnsupported(backend)
        }

        let result = try await pending.session.runCommand(command)
        guard isCurrentPending(pending) else {
            throw SSHSessionManagerError.superseded
        }
        guard result.termination == .exited(status: 0) else {
            throw SSHSessionManagerError.remoteSessionCreateFailed(failureDescription(for: result))
        }

        let entries = await sessionDiscovery(pending.session)
        guard isCurrentPending(pending) else {
            throw SSHSessionManagerError.superseded
        }
        guard let match = matchingEntry(in: entries, backend: backend, name: name) else {
            throw SSHSessionManagerError.remoteSessionNotFound(name)
        }
        await chooseRemoteSession(match)
    }

    func disconnect() async {
        connectionGeneration += 1
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
        restoredPTY = (
            profileID: cached.profileID,
            configuration: PTYConfiguration(
                cols: cached.ptyConfiguration.cols,
                rows: cached.ptyConfiguration.rows,
                term: cached.ptyConfiguration.term
            )
        )
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

        let generation = connectionGeneration

        state = .backgrounded(profileID: profile.id)

        await saveTerminalState(profileID: profile.id, session: session, wasExplicitQuit: false)

        let taskID = backgroundTaskProvider.beginBackgroundTask(
            name: "ssh-keepalive"
        ) { [weak self] in
            Task { @MainActor [weak self] in
                await self?.expireBackgroundTask(session: session, generation: generation)
            }
        }
        backgroundTaskID = taskID
    }

    func handleBackgroundExpiration() async {
        guard let session = activeSession else {
            endBackgroundTaskIfNeeded()
            return
        }
        await expireBackgroundTask(session: session, generation: connectionGeneration)
    }

    private func expireBackgroundTask(session: SSHSession, generation: Int) async {
        guard generation == connectionGeneration, activeSession === session else { return }
        await session.disconnect()
        endBackgroundTaskIfNeeded()
    }

    private func handleEnteredForeground() async {
        guard case .backgrounded(let profileID) = state else { return }
        guard let profile = activeProfile, profile.id == profileID else { return }

        let expected = connectionGeneration

        endBackgroundTaskIfNeeded()

        var wasConnected = false
        if let session = activeSession {
            wasConnected = await session.connectionState == .connected
        }
        guard expected == connectionGeneration else { return }

        if wasConnected {
            state = .active(profileID: profileID)
            return
        }

        guard profile.autoReconnect else {
            state = .idle
            activeSession = nil
            activeProfile = nil
            return
        }

        let hasNetwork = await networkPathProvider.currentPathSatisfied()
        guard expected == connectionGeneration else { return }
        guard hasNetwork else {
            state = .idle
            activeSession = nil
            activeProfile = nil
            return
        }

        let previousPTY = await activeSession?.ptyConfiguration
        guard expected == connectionGeneration else { return }

        state = .reconnecting(profileID: profileID)

        connectionGeneration += 1
        let generation = connectionGeneration

        let session = SSHSession(connectionHandler: connectionHandlerFactory())
        if let previousPTY {
            await session.requestPTY(
                cols: previousPTY.cols,
                rows: previousPTY.rows,
                term: previousPTY.term
            )
        }
        guard generation == connectionGeneration else {
            await session.disconnect()
            return
        }

        do {
            try await session.connect(profile: profile)
        } catch {
            guard generation == connectionGeneration else { return }
            state = .idle
            activeSession = nil
            activeProfile = nil
            return
        }

        guard generation == connectionGeneration else {
            await session.disconnect()
            return
        }

        guard let target = reconnectTarget else {
            activeSession = session
            state = .active(profileID: profileID)
            return
        }

        let entries = await sessionDiscovery(session)
        guard generation == connectionGeneration else {
            await session.disconnect()
            return
        }

        guard let match = matchingEntry(in: entries, backend: target.backend, name: target.name) else {
            activeSession = nil
            hold(
                session: session,
                profileID: profileID,
                generation: generation,
                entries: entries,
                missingName: target.name
            )
            return
        }

        await session.setShellCommand(match.attachCommand)
        guard generation == connectionGeneration else {
            await session.disconnect()
            return
        }
        activeSession = session
        state = .active(profileID: profileID)
    }

    // MARK: - Private

    private func cleanupCurrentSession() async {
        scenePhaseTask?.cancel()
        scenePhaseTask = nil
        let pending = pendingAttach
        pendingAttach = nil
        sessionChoice = nil
        reconnectTarget = nil
        if let session = activeSession {
            await session.disconnect()
        }
        if let pending {
            await pending.session.disconnect()
        }
        endBackgroundTaskIfNeeded()
    }

    private func resolveAttachment(
        for preference: SessionAttachPreference,
        session: SSHSession,
        generation: Int
    ) async throws -> AttachResolution {
        switch preference {
        case .shell:
            return .attach(nil)
        case .pick:
            let entries = try await discoverSessions(on: session, generation: generation)
            if entries.isEmpty {
                return .attach(nil)
            }
            return .choose(entries: entries, missingName: nil)
        case .always(let backend, let name):
            let entries = try await discoverSessions(on: session, generation: generation)
            if let match = matchingEntry(in: entries, backend: backend, name: name) {
                return .attach(match)
            }
            guard let command = createCommand(for: backend, name: name) else {
                return .choose(entries: entries, missingName: name)
            }
            let result = try? await session.runCommand(command)
            try await ensureCurrent(generation, disconnecting: session)
            guard let result, result.termination == .exited(status: 0) else {
                return .choose(entries: entries, missingName: name)
            }
            let refreshed = try await discoverSessions(on: session, generation: generation)
            if let match = matchingEntry(in: refreshed, backend: backend, name: name) {
                return .attach(match)
            }
            return .choose(entries: refreshed, missingName: name)
        }
    }

    private func discoverSessions(on session: SSHSession, generation: Int) async throws -> [RemoteSessionEntry] {
        let entries = await sessionDiscovery(session)
        try await ensureCurrent(generation, disconnecting: session)
        return entries
    }

    private func ensureCurrent(_ generation: Int, disconnecting session: SSHSession) async throws {
        guard generation == connectionGeneration else {
            await session.disconnect()
            throw SSHSessionManagerError.superseded
        }
    }

    private func isCurrentPending(_ pending: PendingAttach) -> Bool {
        pending.generation == connectionGeneration && pendingAttach?.session === pending.session
    }

    private func activate(session: SSHSession, profileID: UUID, entry: RemoteSessionEntry?) {
        reconnectTarget = entry.map { AttachTarget(backend: $0.backend, name: $0.name) }
        pendingAttach = nil
        sessionChoice = nil
        activeSession = session
        state = .active(profileID: profileID)
        if scenePhaseTask == nil {
            startScenePhaseObservation()
        }
    }

    private func hold(
        session: SSHSession,
        profileID: UUID,
        generation: Int,
        entries: [RemoteSessionEntry],
        missingName: String?
    ) {
        pendingAttach = PendingAttach(session: session, profileID: profileID, generation: generation)
        sessionChoice = RemoteSessionChoice(profileID: profileID, entries: entries, missingName: missingName)
    }

    private func matchingEntry(
        in entries: [RemoteSessionEntry],
        backend: SessionBackendKind,
        name: String
    ) -> RemoteSessionEntry? {
        entries.first { $0.backend == backend && $0.name == name }
    }

    private func createCommand(for backend: SessionBackendKind, name: String) -> String? {
        sessionBackends.first { $0.kind == backend }?.createCommand(name: name)
    }

    private func failureDescription(for result: CommandResult) -> String {
        let stderr = String(decoding: result.stderr, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty {
            return stderr
        }
        switch result.termination {
        case .exited(let status):
            return "exit status \(status)"
        case .signaled(let name):
            return "terminated by signal \(name)"
        case .failed(let message):
            return message
        case .closedWithoutStatus:
            return "closed without exit status"
        }
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
