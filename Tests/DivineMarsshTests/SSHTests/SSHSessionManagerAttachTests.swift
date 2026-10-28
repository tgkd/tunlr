import Testing
import Foundation
@testable import DivineMarssh

final class AttachTestDiscovery: @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [[RemoteSessionEntry]]
    private var calls = 0

    init(_ responses: [[RemoteSessionEntry]] = []) {
        self.responses = responses
    }

    var callCount: Int {
        lock.withLock { calls }
    }

    func next() -> [RemoteSessionEntry] {
        lock.withLock {
            calls += 1
            if responses.count > 1 {
                return responses.removeFirst()
            }
            return responses.first ?? []
        }
    }
}

struct AttachTestBackend: RemoteSessionBackend {
    let kind: SessionBackendKind
    let listCommand = "fake-list"
    let createPrefix: String?

    func parse(listOutput: String) -> [RemoteSessionEntry] {
        []
    }

    func createCommand(name: String) -> String? {
        guard let createPrefix else {
            return nil
        }
        return "\(createPrefix) \(name)"
    }
}

struct SSHSessionManagerAttachTests {
    private let workEntry = RemoteSessionEntry(
        backend: .tmux,
        targetID: "$1",
        name: "work",
        detail: "2 windows",
        attachCommand: "tmux attach-session -t '$1'"
    )

    private let notesEntry = RemoteSessionEntry(
        backend: .zmx,
        targetID: "notes",
        name: "notes",
        detail: "",
        attachCommand: "zmx attach notes"
    )

    private func makeProfile(
        attach: SessionAttachPreference,
        autoReconnect: Bool = false
    ) -> SSHConnectionProfile {
        SSHConnectionProfile(
            host: "test.example.com",
            port: 22,
            username: "testuser",
            authMethod: .password,
            autoReconnect: autoReconnect,
            sessionAttach: attach
        )
    }

    @MainActor
    private func makeManager(
        client: MockSSHClient,
        discovery: AttachTestDiscovery,
        backends: [any RemoteSessionBackend] = []
    ) throws -> SSHSessionManager {
        let handler = MockConnectionHandler(client: client)
        let store = try ProfileStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        return SSHSessionManager(
            connectionHandlerFactory: { handler },
            profileStore: store,
            scenePhaseProvider: MockScenePhaseProvider(),
            networkPathProvider: MockNetworkPathProvider(),
            backgroundTaskProvider: MockBackgroundTaskProvider(),
            sessionDiscovery: { _ in discovery.next() },
            sessionBackends: backends
        )
    }

    @MainActor
    private func backgroundAndReconnect(_ manager: SSHSessionManager) async {
        await manager.handleScenePhaseChange(.background)
        await manager.handleBackgroundExpiration()
        await manager.handleScenePhaseChange(.active)
    }

    @Test @MainActor func shellPreferenceNeverDiscovers() async throws {
        let discovery = AttachTestDiscovery([[workEntry]])
        let manager = try makeManager(client: MockSSHClient(), discovery: discovery)
        let profile = makeProfile(attach: .shell)

        try await manager.startSession(for: profile)

        #expect(discovery.callCount == 0)
        #expect(manager.state == .active(profileID: profile.id))
        #expect(manager.sessionChoice == nil)
        let session = try #require(manager.activeSession)
        #expect(await session.shellCommand == nil)
    }

    @Test @MainActor func pickWithEntriesPublishesChoice() async throws {
        let client = MockSSHClient()
        let discovery = AttachTestDiscovery([[workEntry, notesEntry]])
        let manager = try makeManager(client: client, discovery: discovery)
        let profile = makeProfile(attach: .pick)

        try await manager.startSession(for: profile)

        #expect(discovery.callCount == 1)
        #expect(manager.activeSession == nil)
        #expect(manager.state != .active(profileID: profile.id))
        #expect(manager.activeProfile?.id == profile.id)
        let choice = try #require(manager.sessionChoice)
        #expect(choice.profileID == profile.id)
        #expect(choice.entries == [workEntry, notesEntry])
        #expect(choice.missingName == nil)
        #expect(!client.closeCalled)
    }

    @Test @MainActor func pickWithNoEntriesAttachesShell() async throws {
        let discovery = AttachTestDiscovery([[]])
        let manager = try makeManager(client: MockSSHClient(), discovery: discovery)
        let profile = makeProfile(attach: .pick)

        try await manager.startSession(for: profile)

        #expect(discovery.callCount == 1)
        #expect(manager.sessionChoice == nil)
        #expect(manager.state == .active(profileID: profile.id))
        let session = try #require(manager.activeSession)
        #expect(await session.shellCommand == nil)
    }

    @Test @MainActor func chooseRemoteSessionAttachesEntry() async throws {
        let discovery = AttachTestDiscovery([[workEntry, notesEntry]])
        let manager = try makeManager(client: MockSSHClient(), discovery: discovery)
        let profile = makeProfile(attach: .pick)

        try await manager.startSession(for: profile)
        await manager.chooseRemoteSession(notesEntry)

        #expect(manager.sessionChoice == nil)
        #expect(manager.state == .active(profileID: profile.id))
        let session = try #require(manager.activeSession)
        #expect(await session.shellCommand == notesEntry.attachCommand)
    }

    @Test @MainActor func choosingNilAttachesPlainShell() async throws {
        let discovery = AttachTestDiscovery([[workEntry]])
        let manager = try makeManager(client: MockSSHClient(), discovery: discovery)
        let profile = makeProfile(attach: .pick)

        try await manager.startSession(for: profile)
        await manager.chooseRemoteSession(nil)

        #expect(manager.sessionChoice == nil)
        #expect(manager.state == .active(profileID: profile.id))
        let session = try #require(manager.activeSession)
        #expect(await session.shellCommand == nil)
    }

    @Test @MainActor func chooseWithoutPendingSessionIsNoOp() async throws {
        let manager = try makeManager(client: MockSSHClient(), discovery: AttachTestDiscovery())

        await manager.chooseRemoteSession(workEntry)

        #expect(manager.activeSession == nil)
        #expect(manager.state == .idle)
    }

    @Test @MainActor func chooseAfterAttachIsNoOp() async throws {
        let discovery = AttachTestDiscovery([[workEntry, notesEntry]])
        let manager = try makeManager(client: MockSSHClient(), discovery: discovery)

        try await manager.startSession(for: makeProfile(attach: .pick))
        await manager.chooseRemoteSession(workEntry)
        await manager.chooseRemoteSession(notesEntry)

        let session = try #require(manager.activeSession)
        #expect(await session.shellCommand == workEntry.attachCommand)
    }

    @Test @MainActor func alwaysWithMatchAttachesDirectly() async throws {
        let client = MockSSHClient()
        let discovery = AttachTestDiscovery([[notesEntry, workEntry]])
        let manager = try makeManager(
            client: client,
            discovery: discovery,
            backends: [AttachTestBackend(kind: .tmux, createPrefix: "fake-create")]
        )
        let profile = makeProfile(attach: .always(backend: .tmux, name: "work"))

        try await manager.startSession(for: profile)

        #expect(manager.sessionChoice == nil)
        #expect(manager.state == .active(profileID: profile.id))
        #expect(client.executedCommands.isEmpty)
        let session = try #require(manager.activeSession)
        #expect(await session.shellCommand == workEntry.attachCommand)
    }

    @Test @MainActor func alwaysMatchesOnBackendAndName() async throws {
        let sameNameOtherBackend = RemoteSessionEntry(
            backend: .zmx,
            targetID: "work",
            name: "work",
            detail: "",
            attachCommand: "zmx attach work"
        )
        let discovery = AttachTestDiscovery([[sameNameOtherBackend, workEntry]])
        let manager = try makeManager(client: MockSSHClient(), discovery: discovery)

        try await manager.startSession(for: makeProfile(attach: .always(backend: .tmux, name: "work")))

        let session = try #require(manager.activeSession)
        #expect(await session.shellCommand == workEntry.attachCommand)
    }

    @Test @MainActor func alwaysMissingCreatesAndAttaches() async throws {
        let client = MockSSHClient()
        let discovery = AttachTestDiscovery([[notesEntry], [notesEntry, workEntry]])
        let manager = try makeManager(
            client: client,
            discovery: discovery,
            backends: [AttachTestBackend(kind: .tmux, createPrefix: "fake-create")]
        )
        let profile = makeProfile(attach: .always(backend: .tmux, name: "work"))

        try await manager.startSession(for: profile)

        #expect(client.executedCommands == ["fake-create work"])
        #expect(discovery.callCount == 2)
        #expect(manager.sessionChoice == nil)
        #expect(manager.state == .active(profileID: profile.id))
        let session = try #require(manager.activeSession)
        #expect(await session.shellCommand == workEntry.attachCommand)
    }

    @Test @MainActor func alwaysMissingWithoutCreateCommandPublishesChoice() async throws {
        let client = MockSSHClient()
        let discovery = AttachTestDiscovery([[notesEntry]])
        let manager = try makeManager(
            client: client,
            discovery: discovery,
            backends: [AttachTestBackend(kind: .tmux, createPrefix: nil)]
        )
        let profile = makeProfile(attach: .always(backend: .tmux, name: "work"))

        try await manager.startSession(for: profile)

        #expect(client.executedCommands.isEmpty)
        #expect(manager.activeSession == nil)
        let choice = try #require(manager.sessionChoice)
        #expect(choice.profileID == profile.id)
        #expect(choice.entries == [notesEntry])
        #expect(choice.missingName == "work")
    }

    @Test @MainActor func alwaysMissingWithNoEntriesStillPublishesChoice() async throws {
        let discovery = AttachTestDiscovery([[]])
        let manager = try makeManager(client: MockSSHClient(), discovery: discovery)
        let profile = makeProfile(attach: .always(backend: .agterm, name: "build"))

        try await manager.startSession(for: profile)

        #expect(manager.activeSession == nil)
        let choice = try #require(manager.sessionChoice)
        #expect(choice.entries.isEmpty)
        #expect(choice.missingName == "build")
    }

    @Test @MainActor func alwaysCreateFailurePublishesChoice() async throws {
        let client = MockSSHClient()
        client.commandResults["fake-create work"] = CommandResult(
            stdout: Data(),
            stderr: Data("no server".utf8),
            termination: .exited(status: 1)
        )
        let discovery = AttachTestDiscovery([[notesEntry]])
        let manager = try makeManager(
            client: client,
            discovery: discovery,
            backends: [AttachTestBackend(kind: .tmux, createPrefix: "fake-create")]
        )

        try await manager.startSession(for: makeProfile(attach: .always(backend: .tmux, name: "work")))

        #expect(client.executedCommands == ["fake-create work"])
        #expect(discovery.callCount == 1)
        #expect(manager.activeSession == nil)
        #expect(manager.sessionChoice?.missingName == "work")
    }

    @Test @MainActor func alwaysCreatedButNotListedPublishesChoice() async throws {
        let client = MockSSHClient()
        let discovery = AttachTestDiscovery([[notesEntry]])
        let manager = try makeManager(
            client: client,
            discovery: discovery,
            backends: [AttachTestBackend(kind: .tmux, createPrefix: "fake-create")]
        )

        try await manager.startSession(for: makeProfile(attach: .always(backend: .tmux, name: "work")))

        #expect(client.executedCommands == ["fake-create work"])
        #expect(discovery.callCount == 2)
        #expect(manager.activeSession == nil)
        #expect(manager.sessionChoice?.missingName == "work")
    }

    @Test @MainActor func createRemoteSessionRunsCommandAndAttaches() async throws {
        let client = MockSSHClient()
        let discovery = AttachTestDiscovery([[notesEntry], [notesEntry, workEntry]])
        let manager = try makeManager(
            client: client,
            discovery: discovery,
            backends: [AttachTestBackend(kind: .tmux, createPrefix: "fake-create")]
        )
        let profile = makeProfile(attach: .pick)

        try await manager.startSession(for: profile)
        try await manager.createRemoteSession(backend: .tmux, name: "work")

        #expect(client.executedCommands == ["fake-create work"])
        #expect(manager.sessionChoice == nil)
        #expect(manager.state == .active(profileID: profile.id))
        let session = try #require(manager.activeSession)
        #expect(await session.shellCommand == workEntry.attachCommand)
    }

    @Test @MainActor func createRemoteSessionFailureThrowsStderr() async throws {
        let client = MockSSHClient()
        client.commandResults["fake-create work"] = CommandResult(
            stdout: Data(),
            stderr: Data("duplicate session: work\n".utf8),
            termination: .exited(status: 1)
        )
        let discovery = AttachTestDiscovery([[notesEntry]])
        let manager = try makeManager(
            client: client,
            discovery: discovery,
            backends: [AttachTestBackend(kind: .tmux, createPrefix: "fake-create")]
        )

        try await manager.startSession(for: makeProfile(attach: .pick))

        await #expect(throws: SSHSessionManagerError.remoteSessionCreateFailed("duplicate session: work")) {
            try await manager.createRemoteSession(backend: .tmux, name: "work")
        }
        #expect(manager.activeSession == nil)
        #expect(manager.sessionChoice != nil)
        #expect(!client.closeCalled)
    }

    @Test @MainActor func createRemoteSessionFailureWithoutStderrDescribesStatus() async throws {
        let client = MockSSHClient()
        client.commandResults["fake-create work"] = CommandResult(
            stdout: Data(),
            stderr: Data(),
            termination: .exited(status: 127)
        )
        let manager = try makeManager(
            client: client,
            discovery: AttachTestDiscovery([[notesEntry]]),
            backends: [AttachTestBackend(kind: .tmux, createPrefix: "fake-create")]
        )

        try await manager.startSession(for: makeProfile(attach: .pick))

        await #expect(throws: SSHSessionManagerError.remoteSessionCreateFailed("exit status 127")) {
            try await manager.createRemoteSession(backend: .tmux, name: "work")
        }
    }

    @Test @MainActor func createRemoteSessionWithoutCreateCommandThrows() async throws {
        let client = MockSSHClient()
        let manager = try makeManager(
            client: client,
            discovery: AttachTestDiscovery([[notesEntry]]),
            backends: [AttachTestBackend(kind: .tmux, createPrefix: nil)]
        )

        try await manager.startSession(for: makeProfile(attach: .pick))

        await #expect(throws: SSHSessionManagerError.remoteSessionCreateUnsupported(.tmux)) {
            try await manager.createRemoteSession(backend: .tmux, name: "work")
        }
        #expect(client.executedCommands.isEmpty)
        #expect(manager.sessionChoice != nil)
    }

    @Test @MainActor func createRemoteSessionNotListedAfterCreateThrows() async throws {
        let manager = try makeManager(
            client: MockSSHClient(),
            discovery: AttachTestDiscovery([[notesEntry]]),
            backends: [AttachTestBackend(kind: .tmux, createPrefix: "fake-create")]
        )

        try await manager.startSession(for: makeProfile(attach: .pick))

        await #expect(throws: SSHSessionManagerError.remoteSessionNotFound("work")) {
            try await manager.createRemoteSession(backend: .tmux, name: "work")
        }
        #expect(manager.activeSession == nil)
    }

    @Test @MainActor func createRemoteSessionWithoutPendingThrows() async throws {
        let manager = try makeManager(
            client: MockSSHClient(),
            discovery: AttachTestDiscovery(),
            backends: [AttachTestBackend(kind: .tmux, createPrefix: "fake-create")]
        )

        await #expect(throws: SSHSessionManagerError.noPendingSession) {
            try await manager.createRemoteSession(backend: .tmux, name: "work")
        }
    }

    @Test @MainActor func reconnectReattachesSameSessionByName() async throws {
        let movedWorkEntry = RemoteSessionEntry(
            backend: .tmux,
            targetID: "$7",
            name: "work",
            detail: "1 window",
            attachCommand: "tmux attach-session -t '$7'"
        )
        let discovery = AttachTestDiscovery([[workEntry, notesEntry], [notesEntry, movedWorkEntry]])
        let manager = try makeManager(client: MockSSHClient(), discovery: discovery)
        let profile = makeProfile(attach: .pick, autoReconnect: true)

        try await manager.startSession(for: profile)
        await manager.chooseRemoteSession(workEntry)
        let firstSession = try #require(manager.activeSession)

        await backgroundAndReconnect(manager)

        #expect(discovery.callCount == 2)
        #expect(manager.state == .active(profileID: profile.id))
        #expect(manager.sessionChoice == nil)
        let session = try #require(manager.activeSession)
        #expect(session !== firstSession)
        #expect(await session.shellCommand == movedWorkEntry.attachCommand)
    }

    @Test @MainActor func reconnectAfterAlwaysReattaches() async throws {
        let discovery = AttachTestDiscovery([[workEntry]])
        let manager = try makeManager(client: MockSSHClient(), discovery: discovery)
        let profile = makeProfile(attach: .always(backend: .tmux, name: "work"), autoReconnect: true)

        try await manager.startSession(for: profile)
        await backgroundAndReconnect(manager)

        #expect(discovery.callCount == 2)
        #expect(manager.state == .active(profileID: profile.id))
        let session = try #require(manager.activeSession)
        #expect(await session.shellCommand == workEntry.attachCommand)
    }

    @Test @MainActor func reconnectKeepsRestoredPTYSize() async throws {
        let client = MockSSHClient()
        let discovery = AttachTestDiscovery([[workEntry]])
        let manager = try makeManager(client: client, discovery: discovery)
        let profile = makeProfile(attach: .always(backend: .tmux, name: "work"), autoReconnect: true)

        try await manager.startSession(for: profile)
        let firstSession = try #require(manager.activeSession)
        await firstSession.requestPTY(cols: 132, rows: 40)

        await backgroundAndReconnect(manager)

        let session = try #require(manager.activeSession)
        let pty = await session.ptyConfiguration
        #expect(pty.cols == 132)
        #expect(pty.rows == 40)
    }

    @Test @MainActor func reconnectWithTargetGonePublishesMissingName() async throws {
        let discovery = AttachTestDiscovery([[workEntry, notesEntry], [notesEntry]])
        let manager = try makeManager(client: MockSSHClient(), discovery: discovery)
        let profile = makeProfile(attach: .pick, autoReconnect: true)

        try await manager.startSession(for: profile)
        await manager.chooseRemoteSession(workEntry)

        await backgroundAndReconnect(manager)

        #expect(manager.activeSession == nil)
        #expect(manager.state == .reconnecting(profileID: profile.id))
        let choice = try #require(manager.sessionChoice)
        #expect(choice.profileID == profile.id)
        #expect(choice.entries == [notesEntry])
        #expect(choice.missingName == "work")

        await manager.chooseRemoteSession(notesEntry)

        #expect(manager.sessionChoice == nil)
        #expect(manager.state == .active(profileID: profile.id))
        let session = try #require(manager.activeSession)
        #expect(await session.shellCommand == notesEntry.attachCommand)
    }

    @Test @MainActor func reconnectWithoutTargetSkipsDiscovery() async throws {
        let discovery = AttachTestDiscovery([[workEntry]])
        let manager = try makeManager(client: MockSSHClient(), discovery: discovery)
        let profile = makeProfile(attach: .pick, autoReconnect: true)

        try await manager.startSession(for: profile)
        await manager.chooseRemoteSession(nil)

        await backgroundAndReconnect(manager)

        #expect(discovery.callCount == 1)
        #expect(manager.state == .active(profileID: profile.id))
        let session = try #require(manager.activeSession)
        #expect(await session.shellCommand == nil)
    }

    @Test @MainActor func disconnectWhilePickingClearsPendingSession() async throws {
        let client = MockSSHClient()
        let discovery = AttachTestDiscovery([[workEntry]])
        let manager = try makeManager(client: client, discovery: discovery)

        try await manager.startSession(for: makeProfile(attach: .pick))
        await manager.disconnect()

        #expect(client.closeCalled)
        #expect(manager.sessionChoice == nil)
        #expect(manager.state == .idle)
        #expect(manager.activeProfile == nil)

        await manager.chooseRemoteSession(workEntry)

        #expect(manager.activeSession == nil)
        #expect(manager.state == .idle)
    }

    @Test @MainActor func disconnectForgetsReconnectTarget() async throws {
        let discovery = AttachTestDiscovery([[workEntry]])
        let manager = try makeManager(client: MockSSHClient(), discovery: discovery)

        try await manager.startSession(for: makeProfile(attach: .always(backend: .tmux, name: "work")))
        await manager.disconnect()
        #expect(discovery.callCount == 1)

        let shellProfile = makeProfile(attach: .shell, autoReconnect: true)
        try await manager.startSession(for: shellProfile)
        await backgroundAndReconnect(manager)

        #expect(discovery.callCount == 1)
        #expect(manager.state == .active(profileID: shellProfile.id))
        let session = try #require(manager.activeSession)
        #expect(await session.shellCommand == nil)
    }

    @Test @MainActor func pickAfterLiveSessionDropsStaleActiveSession() async throws {
        let discovery = AttachTestDiscovery([[workEntry]])
        let manager = try makeManager(client: MockSSHClient(), discovery: discovery)

        try await manager.startSession(for: makeProfile(attach: .shell))
        #expect(manager.activeSession != nil)

        let pickProfile = makeProfile(attach: .pick)
        try await manager.startSession(for: pickProfile)

        #expect(manager.activeSession == nil)
        #expect(manager.activeProfile?.id == pickProfile.id)
        #expect(manager.sessionChoice?.entries == [workEntry])
    }

    @Test @MainActor func startingNewSessionDiscardsPendingChoice() async throws {
        let discovery = AttachTestDiscovery([[workEntry]])
        let manager = try makeManager(client: MockSSHClient(), discovery: discovery)

        try await manager.startSession(for: makeProfile(attach: .pick))
        #expect(manager.sessionChoice != nil)

        let shellProfile = makeProfile(attach: .shell)
        try await manager.startSession(for: shellProfile)

        #expect(manager.sessionChoice == nil)
        #expect(manager.state == .active(profileID: shellProfile.id))

        await manager.chooseRemoteSession(workEntry)

        let session = try #require(manager.activeSession)
        #expect(await session.shellCommand == nil)
    }
}
