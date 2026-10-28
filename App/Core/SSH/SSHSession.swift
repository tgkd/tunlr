import Foundation

enum ShellOutput: Sendable {
    case stdout(Data)
    case stderr(Data)
}

struct PTYConfiguration: Sendable, Equatable {
    var cols: Int
    var rows: Int
    var term: String

    init(cols: Int = 80, rows: Int = 24, term: String = "xterm-256color") {
        self.cols = cols
        self.rows = rows
        self.term = term
    }
}

enum SSHSessionError: Error, Equatable {
    case notConnected
    case alreadyConnected
    case noActiveShell
    case authenticationFailed
    case unsupportedKeyType(String)
}

// MARK: - Testability Protocols

protocol SSHConnectionHandling: Sendable {
    func connect(profile: SSHConnectionProfile) async throws -> any SSHClientWrapping
}

protocol SSHClientWrapping: AnyObject, Sendable {
    var isConnected: Bool { get }
    func close() async throws
    func onDisconnect(perform: @escaping @Sendable () -> Void)
    func openShell(
        pty: PTYConfiguration,
        onOutput: @escaping @Sendable (ShellOutput) -> Void,
        onEnd: @escaping @Sendable () -> Void
    ) async throws -> any SSHShellHandle
}

protocol SSHShellHandle: Sendable {
    func write(_ data: Data) async throws
    func changeWindowSize(cols: Int, rows: Int) async throws
    func cancel()
}

// MARK: - SSHSession Actor

actor SSHSession {
    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var ptyConfiguration: PTYConfiguration = PTYConfiguration()

    private var client: (any SSHClientWrapping)?
    private var shellHandle: (any SSHShellHandle)?
    private var keepaliveTask: Task<Void, Never>?
    private var stateContinuations: [UUID: AsyncStream<ConnectionState>.Continuation] = [:]

    private let connectionHandler: any SSHConnectionHandling

    init(connectionHandler: any SSHConnectionHandling) {
        self.connectionHandler = connectionHandler
    }

    init(
        hostKeyVerifier: HostKeyVerifier,
        keyManager: KeyManager,
        profileStore: ProfileStore
    ) {
        self.connectionHandler = NIOSSHConnectionHandler(
            hostKeyVerifier: hostKeyVerifier,
            keyManager: keyManager,
            profileStore: profileStore
        )
    }

    func connectionStateStream() -> AsyncStream<ConnectionState> {
        let id = UUID()
        return AsyncStream { continuation in
            continuation.yield(self.connectionState)
            self.stateContinuations[id] = continuation
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { await self?.removeStateContinuation(id: id) }
            }
        }
    }

    func connect(profile: SSHConnectionProfile) async throws {
        guard connectionState == .disconnected else {
            throw SSHSessionError.alreadyConnected
        }

        updateState(.connecting)

        do {
            let newClient = try await connectionHandler.connect(profile: profile)
            self.client = newClient
            updateState(.connected)

            newClient.onDisconnect { [weak self] in
                Task { await self?.handleUnexpectedDisconnect() }
            }

            startKeepalive(interval: profile.keepaliveInterval)
        } catch {
            updateState(.disconnected)
            throw error
        }
    }

    func disconnect() async {
        keepaliveTask?.cancel()
        keepaliveTask = nil

        shellHandle?.cancel()
        shellHandle = nil

        if let client {
            try? await client.close()
        }
        client = nil
        updateState(.disconnected)
    }

    func requestPTY(cols: Int, rows: Int, term: String = "xterm-256color") {
        ptyConfiguration = PTYConfiguration(cols: cols, rows: rows, term: term)
    }

    func openShellChannel() async throws -> AsyncStream<ShellOutput> {
        guard let client, connectionState == .connected else {
            throw SSHSessionError.notConnected
        }

        let (stream, continuation) = AsyncStream<ShellOutput>.makeStream()

        let handle = try await client.openShell(
            pty: ptyConfiguration,
            onOutput: { data in
                continuation.yield(data)
            },
            onEnd: { [weak self] in
                continuation.finish()
                Task { await self?.handleShellEnded() }
            }
        )

        self.shellHandle = handle
        return stream
    }

    func sendWindowChange(cols: Int, rows: Int) async throws {
        guard let shellHandle else {
            throw SSHSessionError.noActiveShell
        }
        try await shellHandle.changeWindowSize(cols: cols, rows: rows)
        ptyConfiguration.cols = cols
        ptyConfiguration.rows = rows
    }

    func write(_ data: Data) async throws {
        guard let shellHandle else {
            throw SSHSessionError.noActiveShell
        }
        try await shellHandle.write(data)
    }

    // MARK: - Private

    private func updateState(_ state: ConnectionState) {
        connectionState = state
        for continuation in stateContinuations.values {
            continuation.yield(state)
        }
    }

    private func removeStateContinuation(id: UUID) {
        stateContinuations.removeValue(forKey: id)
    }

    private func startKeepalive(interval: TimeInterval) {
        guard interval.isFinite,
              interval >= SSHConnectionProfile.minimumKeepaliveInterval else { return }
        let bounded = min(interval, SSHConnectionProfile.maximumKeepaliveInterval)
        keepaliveTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(bounded))
                guard !Task.isCancelled else { break }
                await self.sendKeepalive()
            }
        }
    }

    private func sendKeepalive() {
        guard connectionState == .connected, let shellHandle else { return }
        Task { try? await shellHandle.write(Data()) }
    }

    private func handleUnexpectedDisconnect() {
        client = nil
        shellHandle = nil
        updateState(.disconnected)
    }

    private func handleShellEnded() async {
        shellHandle = nil
        guard connectionState == .connected else { return }
        await disconnect()
    }
}
