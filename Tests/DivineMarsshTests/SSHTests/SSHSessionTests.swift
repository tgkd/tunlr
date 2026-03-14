import Testing
import Foundation
@testable import DivineMarssh

// MARK: - Mock Types

final class MockSSHClient: SSHClientWrapping, @unchecked Sendable {
    var isConnected: Bool = true
    var closeCalled = false
    var disconnectCallbacks: [@Sendable () -> Void] = []
    var shellOpened = false
    var lastPTY: PTYConfiguration?

    func close() async throws {
        isConnected = false
        closeCalled = true
    }

    func onDisconnect(perform: @escaping @Sendable () -> Void) {
        disconnectCallbacks.append(perform)
    }

    func openShell(
        pty: PTYConfiguration,
        onOutput: @escaping @Sendable (ShellOutput) -> Void,
        onEnd: @escaping @Sendable () -> Void
    ) async throws -> any SSHShellHandle {
        shellOpened = true
        lastPTY = pty
        return MockShellHandle(onOutput: onOutput, onEnd: onEnd)
    }

    func simulateDisconnect() {
        isConnected = false
        for callback in disconnectCallbacks {
            callback()
        }
    }
}

final class MockShellHandle: SSHShellHandle, @unchecked Sendable {
    var writtenData: [Data] = []
    var windowChanges: [(cols: Int, rows: Int)] = []
    var cancelled = false
    let onOutput: @Sendable (ShellOutput) -> Void
    let onEnd: @Sendable () -> Void

    init(
        onOutput: @escaping @Sendable (ShellOutput) -> Void,
        onEnd: @escaping @Sendable () -> Void
    ) {
        self.onOutput = onOutput
        self.onEnd = onEnd
    }

    func write(_ data: Data) async throws {
        writtenData.append(data)
    }

    func changeWindowSize(cols: Int, rows: Int) async throws {
        windowChanges.append((cols: cols, rows: rows))
    }

    func cancel() {
        cancelled = true
    }
}

final class FailingSSHClient: SSHClientWrapping, @unchecked Sendable {
    var isConnected: Bool = false

    func close() async throws {}
    func onDisconnect(perform: @escaping @Sendable () -> Void) {}
    func openShell(
        pty: PTYConfiguration,
        onOutput: @escaping @Sendable (ShellOutput) -> Void,
        onEnd: @escaping @Sendable () -> Void
    ) async throws -> any SSHShellHandle {
        throw SSHSessionError.noActiveShell
    }
}

struct MockConnectionHandler: SSHConnectionHandling {
    let clientToReturn: any SSHClientWrapping
    let shouldFail: Bool
    let error: Error

    init(client: any SSHClientWrapping, shouldFail: Bool = false) {
        self.clientToReturn = client
        self.shouldFail = shouldFail
        self.error = SSHSessionError.authenticationFailed
    }

    init(error: Error) {
        self.clientToReturn = MockSSHClient()
        self.shouldFail = true
        self.error = error
    }

    func connect(profile: SSHConnectionProfile) async throws -> any SSHClientWrapping {
        if shouldFail {
            throw error
        }
        return clientToReturn
    }
}

// MARK: - ConnectionState Tests

struct ConnectionStateTests {
    @Test func allCasesAreDistinct() {
        let states: [ConnectionState] = [.disconnected, .connecting, .connected, .reconnecting]
        for i in 0..<states.count {
            for j in (i + 1)..<states.count {
                #expect(states[i] != states[j])
            }
        }
    }

    @Test func equalityWorks() {
        #expect(ConnectionState.disconnected == ConnectionState.disconnected)
        #expect(ConnectionState.connecting == ConnectionState.connecting)
        #expect(ConnectionState.connected == ConnectionState.connected)
        #expect(ConnectionState.reconnecting == ConnectionState.reconnecting)
    }
}

// MARK: - SSHSession State Transition Tests

struct SSHSessionStateTests {
    private func makeTestProfile() -> SSHConnectionProfile {
        SSHConnectionProfile(
            host: "test.example.com",
            port: 22,
            username: "testuser",
            authMethod: .password
        )
    }

    @Test func initialStateIsDisconnected() async {
        let session = SSHSession(connectionHandler: MockConnectionHandler(client: MockSSHClient()))
        let state = await session.connectionState
        #expect(state == .disconnected)
    }

    @Test func connectTransitionsToConnected() async throws {
        let mockClient = MockSSHClient()
        let session = SSHSession(connectionHandler: MockConnectionHandler(client: mockClient))

        try await session.connect(profile: makeTestProfile())

        let state = await session.connectionState
        #expect(state == .connected)
    }

    @Test func connectFailureReturnsToDisconnected() async {
        let handler = MockConnectionHandler(error: SSHSessionError.authenticationFailed)
        let session = SSHSession(connectionHandler: handler)

        do {
            try await session.connect(profile: makeTestProfile())
            Issue.record("Expected error")
        } catch {
            // Expected
        }

        let state = await session.connectionState
        #expect(state == .disconnected)
    }

    @Test func connectWhenAlreadyConnectedThrows() async throws {
        let mockClient = MockSSHClient()
        let session = SSHSession(connectionHandler: MockConnectionHandler(client: mockClient))
        try await session.connect(profile: makeTestProfile())

        await #expect(throws: SSHSessionError.self) {
            try await session.connect(profile: makeTestProfile())
        }
    }

    @Test func disconnectTransitionsToDisconnected() async throws {
        let mockClient = MockSSHClient()
        let session = SSHSession(connectionHandler: MockConnectionHandler(client: mockClient))
        try await session.connect(profile: makeTestProfile())

        await session.disconnect()

        let state = await session.connectionState
        #expect(state == .disconnected)
        #expect(mockClient.closeCalled)
    }

    @Test func disconnectWhenAlreadyDisconnectedIsNoOp() async {
        let session = SSHSession(connectionHandler: MockConnectionHandler(client: MockSSHClient()))
        await session.disconnect()
        let state = await session.connectionState
        #expect(state == .disconnected)
    }

    @Test func disconnectAfterDisconnectIsNoOp() async throws {
        let mockClient = MockSSHClient()
        let session = SSHSession(connectionHandler: MockConnectionHandler(client: mockClient))
        try await session.connect(profile: makeTestProfile())

        await session.disconnect()
        await session.disconnect()

        let state = await session.connectionState
        #expect(state == .disconnected)
    }

    @Test func stateStreamYieldsCurrentState() async {
        let session = SSHSession(connectionHandler: MockConnectionHandler(client: MockSSHClient()))
        let stream = await session.connectionStateStream()

        var states: [ConnectionState] = []
        for await state in stream {
            states.append(state)
            if states.count >= 1 { break }
        }

        #expect(states == [.disconnected])
    }

    @Test func stateStreamYieldsTransitions() async throws {
        let mockClient = MockSSHClient()
        let session = SSHSession(connectionHandler: MockConnectionHandler(client: mockClient))
        let stream = await session.connectionStateStream()

        var states: [ConnectionState] = []

        // Collect initial state
        for await state in stream {
            states.append(state)
            break
        }

        // Connect
        try await session.connect(profile: makeTestProfile())

        for await state in stream {
            states.append(state)
            if state == .connected { break }
        }

        #expect(states.contains(.disconnected))
        #expect(states.contains(.connected))
    }
}

// MARK: - PTY Configuration Tests

struct PTYConfigurationTests {
    @Test func defaultPTYConfiguration() async {
        let session = SSHSession(connectionHandler: MockConnectionHandler(client: MockSSHClient()))
        let config = await session.ptyConfiguration
        #expect(config.cols == 80)
        #expect(config.rows == 24)
        #expect(config.term == "xterm-256color")
    }

    @Test func requestPTYUpdatesConfiguration() async {
        let session = SSHSession(connectionHandler: MockConnectionHandler(client: MockSSHClient()))
        await session.requestPTY(cols: 120, rows: 40, term: "xterm")

        let config = await session.ptyConfiguration
        #expect(config.cols == 120)
        #expect(config.rows == 40)
        #expect(config.term == "xterm")
    }

    @Test func requestPTYDefaultTerm() async {
        let session = SSHSession(connectionHandler: MockConnectionHandler(client: MockSSHClient()))
        await session.requestPTY(cols: 100, rows: 50)

        let config = await session.ptyConfiguration
        #expect(config.cols == 100)
        #expect(config.rows == 50)
        #expect(config.term == "xterm-256color")
    }

    @Test func ptyConfigurationEquality() {
        let a = PTYConfiguration(cols: 80, rows: 24, term: "xterm-256color")
        let b = PTYConfiguration(cols: 80, rows: 24, term: "xterm-256color")
        let c = PTYConfiguration(cols: 120, rows: 40, term: "xterm")
        #expect(a == b)
        #expect(a != c)
    }

    @Test func ptyConfigurationPassedToShell() async throws {
        let mockClient = MockSSHClient()
        let session = SSHSession(connectionHandler: MockConnectionHandler(client: mockClient))
        try await session.connect(profile: SSHConnectionProfile(
            host: "test", username: "user", authMethod: .password
        ))

        await session.requestPTY(cols: 132, rows: 43, term: "vt100")
        _ = try await session.openShellChannel()

        #expect(mockClient.lastPTY?.cols == 132)
        #expect(mockClient.lastPTY?.rows == 43)
        #expect(mockClient.lastPTY?.term == "vt100")
    }
}

// MARK: - Shell and Write Tests

struct SSHSessionShellTests {
    private func makeTestProfile() -> SSHConnectionProfile {
        SSHConnectionProfile(
            host: "test.example.com",
            port: 22,
            username: "testuser",
            authMethod: .password
        )
    }

    @Test func openShellWhenNotConnectedThrows() async {
        let session = SSHSession(connectionHandler: MockConnectionHandler(client: MockSSHClient()))
        await #expect(throws: SSHSessionError.self) {
            _ = try await session.openShellChannel()
        }
    }

    @Test func writeWhenNoShellThrows() async {
        let session = SSHSession(connectionHandler: MockConnectionHandler(client: MockSSHClient()))
        await #expect(throws: SSHSessionError.self) {
            try await session.write(Data("test".utf8))
        }
    }

    @Test func sendWindowChangeWhenNoShellThrows() async {
        let session = SSHSession(connectionHandler: MockConnectionHandler(client: MockSSHClient()))
        await #expect(throws: SSHSessionError.self) {
            try await session.sendWindowChange(cols: 80, rows: 24)
        }
    }

    @Test func sendWindowChangeUpdatesPTYConfig() async throws {
        let mockClient = MockSSHClient()
        let session = SSHSession(connectionHandler: MockConnectionHandler(client: mockClient))
        try await session.connect(profile: makeTestProfile())
        _ = try await session.openShellChannel()

        try await session.sendWindowChange(cols: 200, rows: 50)

        let config = await session.ptyConfiguration
        #expect(config.cols == 200)
        #expect(config.rows == 50)
    }
}

// MARK: - Error Type Tests

struct SSHSessionErrorTests {
    @Test func errorsAreEquatable() {
        #expect(SSHSessionError.notConnected == SSHSessionError.notConnected)
        #expect(SSHSessionError.alreadyConnected == SSHSessionError.alreadyConnected)
        #expect(SSHSessionError.noActiveShell == SSHSessionError.noActiveShell)
        #expect(SSHSessionError.authenticationFailed == SSHSessionError.authenticationFailed)
        #expect(SSHSessionError.notConnected != SSHSessionError.alreadyConnected)
    }
}

// MARK: - HostKeyValidatorAdapter Tests

struct HostKeyValidatorAdapterTests {
    @Test func extractKeyTypeEd25519() {
        var data = Data()
        let keyType = "ssh-ed25519"
        var len = UInt32(keyType.utf8.count).bigEndian
        data.append(Data(bytes: &len, count: 4))
        data.append(Data(keyType.utf8))
        data.append(Data(repeating: 0xAB, count: 32))

        let result = HostKeyValidatorAdapter.extractKeyType(from: data)
        #expect(result == "ssh-ed25519")
    }

    @Test func extractKeyTypeECDSA() {
        var data = Data()
        let keyType = "ecdsa-sha2-nistp256"
        var len = UInt32(keyType.utf8.count).bigEndian
        data.append(Data(bytes: &len, count: 4))
        data.append(Data(keyType.utf8))

        let result = HostKeyValidatorAdapter.extractKeyType(from: data)
        #expect(result == "ecdsa-sha2-nistp256")
    }

    @Test func extractKeyTypeRSA() {
        var data = Data()
        let keyType = "ssh-rsa"
        var len = UInt32(keyType.utf8.count).bigEndian
        data.append(Data(bytes: &len, count: 4))
        data.append(Data(keyType.utf8))

        let result = HostKeyValidatorAdapter.extractKeyType(from: data)
        #expect(result == "ssh-rsa")
    }

    @Test func extractKeyTypeFromEmptyDataReturnsUnknown() {
        let result = HostKeyValidatorAdapter.extractKeyType(from: Data())
        #expect(result == "unknown")
    }

    @Test func extractKeyTypeFromTruncatedDataReturnsUnknown() {
        let data = Data([0x00, 0x00, 0x00, 0x20])
        let result = HostKeyValidatorAdapter.extractKeyType(from: data)
        #expect(result == "unknown")
    }
}
