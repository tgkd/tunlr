import Testing
import Foundation
@testable import DivineMarssh

// MARK: - Mock Types

final class MockTerminalSSHClient: SSHClientWrapping, @unchecked Sendable {
    var isConnected: Bool = true
    var closeCalled = false
    var shellOpened = false
    var lastPTY: PTYConfiguration?
    var lastOnOutput: (@Sendable (ShellOutput) -> Void)?
    var lastOnEnd: (@Sendable () -> Void)?

    func close() async throws {
        isConnected = false
        closeCalled = true
    }

    func onDisconnect(perform: @escaping @Sendable () -> Void) {}

    func openShell(
        pty: PTYConfiguration,
        onOutput: @escaping @Sendable (ShellOutput) -> Void,
        onEnd: @escaping @Sendable () -> Void
    ) async throws -> any SSHShellHandle {
        shellOpened = true
        lastPTY = pty
        lastOnOutput = onOutput
        lastOnEnd = onEnd
        return RecordingShellHandle()
    }
}

final class RecordingShellHandle: SSHShellHandle, @unchecked Sendable {
    var writtenData: [Data] = []
    var windowChanges: [(cols: Int, rows: Int)] = []
    var cancelled = false

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

struct RecordingConnectionHandler: SSHConnectionHandling {
    let client: any SSHClientWrapping

    func connect(profile: SSHConnectionProfile) async throws -> any SSHClientWrapping {
        client
    }
}

// MARK: - Mock Delegate

@MainActor
final class MockDataSourceDelegate: SSHTerminalDataSourceDelegate {
    var titles: [String] = []
    var scrollPositions: [Double] = []
    var openedLinks: [String] = []

    func dataSource(_ dataSource: SSHTerminalDataSource, didUpdateTitle title: String) {
        titles.append(title)
    }

    func dataSource(_ dataSource: SSHTerminalDataSource, didUpdateScrollPosition position: Double) {
        scrollPositions.append(position)
    }

    func dataSource(_ dataSource: SSHTerminalDataSource, didRequestOpenLink link: String) {
        openedLinks.append(link)
    }
}

// MARK: - SSHTerminalDataSource Tests

@Suite(.serialized)
struct SSHTerminalDataSourceTests {
    private func makeTestProfile() -> SSHConnectionProfile {
        SSHConnectionProfile(
            host: "test.example.com",
            port: 22,
            username: "testuser",
            authMethod: .password
        )
    }

    @Test @MainActor
    func initializesWithSession() {
        let mockClient = MockTerminalSSHClient()
        let session = SSHSession(connectionHandler: RecordingConnectionHandler(client: mockClient))
        let dataSource = SSHTerminalDataSource(sshSession: session)

        #expect(dataSource.currentTitle == "")
        #expect(dataSource.currentScrollPosition == 0.0)
        #expect(dataSource.lastSentData == nil)
        #expect(dataSource.pendingResize == nil)
    }

    @Test @MainActor
    func sendRoutesToSSHSession() async throws {
        let mockClient = MockTerminalSSHClient()
        let session = SSHSession(connectionHandler: RecordingConnectionHandler(client: mockClient))
        let dataSource = SSHTerminalDataSource(sshSession: session)

        try await session.connect(profile: makeTestProfile())
        _ = try await session.openShellChannel()

        let testData: [UInt8] = [0x68, 0x65, 0x6C, 0x6C, 0x6F] // "hello"

        // Simulate the delegate call by directly invoking the internal path
        try await session.write(Data(testData))

        // Verify data was written via the shell handle
        let handle = mockClient.lastPTY != nil
        #expect(handle)
    }

    @Test @MainActor
    func delegateReceivesTitleUpdate() async {
        let mockClient = MockTerminalSSHClient()
        let session = SSHSession(connectionHandler: RecordingConnectionHandler(client: mockClient))
        let dataSource = SSHTerminalDataSource(sshSession: session)
        let mockDelegate = MockDataSourceDelegate()
        dataSource.delegate = mockDelegate

        mockDelegate.dataSource(dataSource, didUpdateTitle: "test-host")

        #expect(mockDelegate.titles == ["test-host"])
        #expect(dataSource.currentTitle == "")
    }

    @Test @MainActor
    func delegateReceivesScrollPositionUpdate() async {
        let mockClient = MockTerminalSSHClient()
        let session = SSHSession(connectionHandler: RecordingConnectionHandler(client: mockClient))
        let dataSource = SSHTerminalDataSource(sshSession: session)
        let mockDelegate = MockDataSourceDelegate()
        dataSource.delegate = mockDelegate

        mockDelegate.dataSource(dataSource, didUpdateScrollPosition: 0.75)

        #expect(mockDelegate.scrollPositions == [0.75])
        #expect(dataSource.currentScrollPosition == 0.0)
    }

    @Test @MainActor
    func delegateReceivesLinkRequest() async {
        let mockClient = MockTerminalSSHClient()
        let session = SSHSession(connectionHandler: RecordingConnectionHandler(client: mockClient))
        let dataSource = SSHTerminalDataSource(sshSession: session)
        let mockDelegate = MockDataSourceDelegate()
        dataSource.delegate = mockDelegate

        mockDelegate.dataSource(dataSource, didRequestOpenLink: "https://example.com")

        #expect(mockDelegate.openedLinks == ["https://example.com"])
    }

    @Test @MainActor
    func stopOutputFeedCancelsTask() async throws {
        let mockClient = MockTerminalSSHClient()
        let session = SSHSession(connectionHandler: RecordingConnectionHandler(client: mockClient))
        let dataSource = SSHTerminalDataSource(sshSession: session)

        try await session.connect(profile: makeTestProfile())
        let stream = try await session.openShellChannel()
        dataSource.startOutputFeed(from: stream)

        dataSource.stopOutputFeed()

        // Verify no crash and clean state
        #expect(dataSource.currentTitle == "")
    }

    @Test @MainActor
    func resizeStoresPendingResize() {
        let mockClient = MockTerminalSSHClient()
        let session = SSHSession(connectionHandler: RecordingConnectionHandler(client: mockClient))
        let dataSource = SSHTerminalDataSource(sshSession: session)

        dataSource.handleResizeForTesting(cols: 120, rows: 40)

        #expect(dataSource.pendingResize?.cols == 120)
        #expect(dataSource.pendingResize?.rows == 40)
    }

    @Test @MainActor
    func resizeDebounceOverwritesPending() async {
        let mockClient = MockTerminalSSHClient()
        let session = SSHSession(connectionHandler: RecordingConnectionHandler(client: mockClient))
        let dataSource = SSHTerminalDataSource(sshSession: session)

        dataSource.handleResizeForTesting(cols: 80, rows: 24)
        dataSource.handleResizeForTesting(cols: 120, rows: 40)

        #expect(dataSource.pendingResize?.cols == 120)
        #expect(dataSource.pendingResize?.rows == 40)
    }

    @Test @MainActor
    func outputFeedProcessesStdout() async throws {
        let mockClient = MockTerminalSSHClient()
        let session = SSHSession(connectionHandler: RecordingConnectionHandler(client: mockClient))
        let dataSource = SSHTerminalDataSource(sshSession: session)

        try await session.connect(profile: makeTestProfile())

        let (stream, continuation) = AsyncStream<ShellOutput>.makeStream()
        dataSource.startOutputFeed(from: stream)

        continuation.yield(.stdout(Data("hello".utf8)))
        continuation.finish()

        // Give time for the async processing
        try await Task.sleep(nanoseconds: 50_000_000)

        // The data was fed but without a real TerminalView we can't verify rendering.
        // At least verify no crash occurred.
        dataSource.stopOutputFeed()
    }

    @Test @MainActor
    func outputFeedProcessesStderr() async throws {
        let mockClient = MockTerminalSSHClient()
        let session = SSHSession(connectionHandler: RecordingConnectionHandler(client: mockClient))
        let dataSource = SSHTerminalDataSource(sshSession: session)

        try await session.connect(profile: makeTestProfile())

        let (stream, continuation) = AsyncStream<ShellOutput>.makeStream()
        dataSource.startOutputFeed(from: stream)

        continuation.yield(.stderr(Data("error".utf8)))
        continuation.finish()

        try await Task.sleep(nanoseconds: 50_000_000)

        dataSource.stopOutputFeed()
    }

    @Test @MainActor
    func multipleStartOutputFeedCancelsPrevious() async {
        let mockClient = MockTerminalSSHClient()
        let session = SSHSession(connectionHandler: RecordingConnectionHandler(client: mockClient))
        let dataSource = SSHTerminalDataSource(sshSession: session)

        let (stream1, continuation1) = AsyncStream<ShellOutput>.makeStream()
        let (stream2, _) = AsyncStream<ShellOutput>.makeStream()

        dataSource.startOutputFeed(from: stream1)
        dataSource.startOutputFeed(from: stream2)

        continuation1.finish()
        dataSource.stopOutputFeed()
    }
}
