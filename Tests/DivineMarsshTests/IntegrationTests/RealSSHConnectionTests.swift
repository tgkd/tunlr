import Testing
import Foundation
@testable import DivineMarssh

extension Tag {
    @Tag static var integration: Self
}

private class BundleToken {}

struct RealSSHConnectionTests {

    private static let host = "127.0.0.1"
    private static let port: UInt16 = 2222
    private static let username = "testuser"
    private static let password = "testpassword"

    private static let serverReachable: Bool = {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr(host)
        let outcome = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { rebound in
                connect(descriptor, rebound, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return outcome == 0
    }()

    private static let keyFixturesAvailable: Bool = {
        let bundle = Bundle(for: BundleToken.self)
        return ["test_ed25519", "test_ecdsa"].allSatisfy {
            bundle.url(forResource: $0, withExtension: nil, subdirectory: "tests-ssh-keys") != nil
        }
    }()

    private struct TestDeps {
        let hostKeyVerifier: HostKeyVerifier
        let knownHostsStore: KnownHostsStore
        let keyManager: KeyManager
        let profileStore: ProfileStore
        let tempDir: URL
        let keychainServiceName: String

        func cleanup() async {
            let allKeys = await keyManager.listAllKeys()
            for key in allKeys {
                try? await keyManager.deleteKey(identity: key)
            }
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    private static func makeDeps() throws -> TestDeps {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RealSSHTest-\(UUID().uuidString)")

        let knownHostsStore = try KnownHostsStore(
            directory: tempDir.appendingPathComponent("hosts")
        )
        let hostKeyVerifier = HostKeyVerifier(store: knownHostsStore)

        let keychainServiceName = "com.divinemarssh.real-test.\(UUID().uuidString)"
        let keychainManager = try KeychainKeyManager(
            directory: tempDir.appendingPathComponent("keys"),
            keychainServiceName: keychainServiceName,
            useBiometricProtection: false
        )
        let seManager = SecureEnclaveKeyManager()
        let keyManager = KeyManager(
            secureEnclaveManager: seManager,
            keychainManager: keychainManager
        )

        let profileStore = try ProfileStore(
            directory: tempDir.appendingPathComponent("profiles")
        )

        return TestDeps(
            hostKeyVerifier: hostKeyVerifier,
            knownHostsStore: knownHostsStore,
            keyManager: keyManager,
            profileStore: profileStore,
            tempDir: tempDir,
            keychainServiceName: keychainServiceName
        )
    }

    private static func makeHandler(_ deps: TestDeps) -> NIOSSHConnectionHandler {
        NIOSSHConnectionHandler(
            hostKeyVerifier: deps.hostKeyVerifier,
            keyManager: deps.keyManager,
            profileStore: deps.profileStore
        )
    }

    private static func loadKeyPEM(named name: String) throws -> Data {
        let bundle = Bundle(for: BundleToken.self)
        guard let url = bundle.url(
            forResource: name,
            withExtension: nil,
            subdirectory: "tests-ssh-keys"
        ) else {
            throw TestError.keyFileNotFound(name)
        }
        return try Data(contentsOf: url)
    }

    private static func readUntil(
        stream: AsyncStream<ShellOutput>,
        containing text: String,
        timeout: Duration = .seconds(10)
    ) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                var output = Data()
                for await chunk in stream {
                    if case .stdout(let data) = chunk {
                        output.append(data)
                    }
                    if let str = String(data: output, encoding: .utf8),
                       str.contains(text) {
                        return str
                    }
                }
                return String(data: output, encoding: .utf8) ?? ""
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw TestError.timeout
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private enum TestError: Error {
        case keyFileNotFound(String)
        case timeout
    }

    // MARK: - Password Auth

    @Test(.tags(.integration), .enabled(if: RealSSHConnectionTests.serverReachable, "requires the docker SSH server on 127.0.0.1:2222 (docker compose up -d)"))
    func passwordAuthConnectAndRunCommand() async throws {
        let deps = try Self.makeDeps()
        defer { Task { await deps.cleanup() } }

        let profile = SSHConnectionProfile(
            host: Self.host, port: Self.port,
            username: Self.username, authMethod: .password
        )
        try await deps.profileStore.addProfile(profile, password: Self.password)

        let session = SSHSession(connectionHandler: Self.makeHandler(deps))
        try await session.connect(profile: profile)

        let state = await session.connectionState
        #expect(state == .connected)

        await session.requestPTY(cols: 80, rows: 24)
        let stream = try await session.openShellChannel()

        try await session.write(Data("echo INTEGRATION_OK\n".utf8))
        let output = try await Self.readUntil(stream: stream, containing: "INTEGRATION_OK")
        #expect(output.contains("INTEGRATION_OK"))

        await session.disconnect()
    }

    // MARK: - Ed25519 Key Auth

    @Test(.tags(.integration), .enabled(if: RealSSHConnectionTests.serverReachable && RealSSHConnectionTests.keyFixturesAvailable, "requires the docker SSH server and the test_ed25519/test_ecdsa bundle fixtures"))
    func ed25519KeyAuthConnect() async throws {
        let deps = try Self.makeDeps()
        defer { Task { await deps.cleanup() } }

        let pemData = try Self.loadKeyPEM(named: "test_ed25519")
        let identity = try await deps.keyManager.importKey(pemData: pemData, label: "test-ed25519")

        let profile = SSHConnectionProfile(
            host: Self.host, port: Self.port,
            username: Self.username,
            authMethod: .importedKey(keyID: identity.id)
        )
        try await deps.profileStore.addProfile(profile)

        let session = SSHSession(connectionHandler: Self.makeHandler(deps))
        try await session.connect(profile: profile)

        let state = await session.connectionState
        #expect(state == .connected)

        await session.requestPTY(cols: 80, rows: 24)
        let stream = try await session.openShellChannel()

        try await session.write(Data("whoami\n".utf8))
        let output = try await Self.readUntil(stream: stream, containing: Self.username)
        #expect(output.contains(Self.username))

        await session.disconnect()
    }

    // MARK: - ECDSA Key Auth

    @Test(.tags(.integration), .enabled(if: RealSSHConnectionTests.serverReachable && RealSSHConnectionTests.keyFixturesAvailable, "requires the docker SSH server and the test_ed25519/test_ecdsa bundle fixtures"))
    func ecdsaKeyAuthConnect() async throws {
        let deps = try Self.makeDeps()
        defer { Task { await deps.cleanup() } }

        let pemData = try Self.loadKeyPEM(named: "test_ecdsa")
        let identity = try await deps.keyManager.importKey(pemData: pemData, label: "test-ecdsa")

        let profile = SSHConnectionProfile(
            host: Self.host, port: Self.port,
            username: Self.username,
            authMethod: .importedKey(keyID: identity.id)
        )
        try await deps.profileStore.addProfile(profile)

        let session = SSHSession(connectionHandler: Self.makeHandler(deps))
        try await session.connect(profile: profile)

        let state = await session.connectionState
        #expect(state == .connected)

        await session.requestPTY(cols: 80, rows: 24)
        let stream = try await session.openShellChannel()

        try await session.write(Data("whoami\n".utf8))
        let output = try await Self.readUntil(stream: stream, containing: Self.username)
        #expect(output.contains(Self.username))

        await session.disconnect()
    }

    // MARK: - Host Key TOFU

    @Test(.tags(.integration), .enabled(if: RealSSHConnectionTests.serverReachable, "requires the docker SSH server on 127.0.0.1:2222 (docker compose up -d)"))
    func hostKeyTOFUFlow() async throws {
        let deps = try Self.makeDeps()
        defer { Task { await deps.cleanup() } }

        let profile = SSHConnectionProfile(
            host: Self.host, port: Self.port,
            username: Self.username, authMethod: .password
        )
        try await deps.profileStore.addProfile(profile, password: Self.password)

        let storedBefore = try await deps.knownHostsStore.allHostKeys()
        #expect(storedBefore.isEmpty)

        let handler = Self.makeHandler(deps)

        let session1 = SSHSession(connectionHandler: handler)
        try await session1.connect(profile: profile)
        await session1.disconnect()

        let storedAfterFirst = try await deps.knownHostsStore.allHostKeys()
        #expect(storedAfterFirst.count == 1)
        #expect(storedAfterFirst.first?.hostname == Self.host)

        let session2 = SSHSession(connectionHandler: handler)
        try await session2.connect(profile: profile)
        await session2.disconnect()

        let storedAfterSecond = try await deps.knownHostsStore.allHostKeys()
        #expect(storedAfterSecond.count == 1)
    }

    // MARK: - Wrong Password

    @Test(.tags(.integration), .enabled(if: RealSSHConnectionTests.serverReachable, "requires the docker SSH server on 127.0.0.1:2222 (docker compose up -d)"))
    func connectionFailsWithWrongPassword() async throws {
        let deps = try Self.makeDeps()
        defer { Task { await deps.cleanup() } }

        let profile = SSHConnectionProfile(
            host: Self.host, port: Self.port,
            username: Self.username, authMethod: .password
        )
        try await deps.profileStore.addProfile(profile, password: "wrongpassword")

        let session = SSHSession(connectionHandler: Self.makeHandler(deps))

        await #expect(throws: Error.self) {
            try await session.connect(profile: profile)
        }

        let state = await session.connectionState
        #expect(state == .disconnected)
    }

    // MARK: - Full PTY Lifecycle

    @Test(.tags(.integration), .enabled(if: RealSSHConnectionTests.serverReachable, "requires the docker SSH server on 127.0.0.1:2222 (docker compose up -d)"))
    func fullPTYLifecycle() async throws {
        let deps = try Self.makeDeps()
        defer { Task { await deps.cleanup() } }

        let profile = SSHConnectionProfile(
            host: Self.host, port: Self.port,
            username: Self.username, authMethod: .password
        )
        try await deps.profileStore.addProfile(profile, password: Self.password)

        let session = SSHSession(connectionHandler: Self.makeHandler(deps))
        try await session.connect(profile: profile)

        await session.requestPTY(cols: 80, rows: 24)
        let stream = try await session.openShellChannel()

        try await session.write(Data("echo HELLO\n".utf8))
        let output1 = try await Self.readUntil(stream: stream, containing: "HELLO")
        #expect(output1.contains("HELLO"))

        try await session.sendWindowChange(cols: 200, rows: 60)
        let pty = await session.ptyConfiguration
        #expect(pty.cols == 200)
        #expect(pty.rows == 60)

        try await session.write(Data("echo RESIZED\n".utf8))
        let output2 = try await Self.readUntil(stream: stream, containing: "RESIZED")
        #expect(output2.contains("RESIZED"))

        await session.disconnect()
        let state = await session.connectionState
        #expect(state == .disconnected)
    }

    // MARK: - Exec and Attach

    private static func connectWithPassword(_ deps: TestDeps) async throws -> SSHSession {
        let profile = SSHConnectionProfile(
            host: Self.host, port: Self.port,
            username: Self.username, authMethod: .password
        )
        try await deps.profileStore.addProfile(profile, password: Self.password)
        let session = SSHSession(connectionHandler: Self.makeHandler(deps))
        try await session.connect(profile: profile)
        return session
    }

    private static func waitForTermination(_ session: SSHSession) async throws -> SessionTermination {
        for _ in 0..<50 {
            if let termination = await session.lastTermination {
                return termination
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw TestError.timeout
    }

    @Test(.tags(.integration), .enabled(if: RealSSHConnectionTests.serverReachable, "requires the docker SSH server on 127.0.0.1:2222 (docker compose up -d)"))
    func execCommandReportsOutputAndExitStatus() async throws {
        let deps = try Self.makeDeps()
        defer { Task { await deps.cleanup() } }
        let session = try await Self.connectWithPassword(deps)

        let result = try await session.runCommand("echo EXEC_OK; echo EXEC_ERR >&2; exit 3")
        #expect(result.standardOutput == "EXEC_OK\n")
        #expect(String(decoding: result.stderr, as: UTF8.self) == "EXEC_ERR\n")
        #expect(result.termination == .exited(status: 3))

        await session.disconnect()
    }

    @Test(.tags(.integration), .enabled(if: RealSSHConnectionTests.serverReachable, "requires the docker SSH server with tmux (docker compose up -d)"))
    func attachToMissingTmuxSessionReportsFailure() async throws {
        let deps = try Self.makeDeps()
        defer { Task { await deps.cleanup() } }
        let session = try await Self.connectWithPassword(deps)

        await session.requestPTY(cols: 80, rows: 24)
        let stream = try await session.openShellChannel(
            command: "tmux attach-session -t 'tunlr-missing-\(UUID().uuidString)'"
        )
        for await _ in stream {}

        let termination = try await Self.waitForTermination(session)
        #expect(termination != .exited(status: 0))
        if case .exited(let status) = termination {
            #expect(status != 0)
        } else {
            Issue.record("expected an exit status, got \(termination)")
        }

        await session.disconnect()
    }

    @Test(.tags(.integration), .enabled(if: RealSSHConnectionTests.serverReachable, "requires the docker SSH server with tmux (docker compose up -d)"))
    func attachToExistingTmuxSession() async throws {
        let deps = try Self.makeDeps()
        defer { Task { await deps.cleanup() } }
        let name = "tunlr-\(UUID().uuidString.prefix(8))"

        let setup = try await Self.connectWithPassword(deps)
        let created = try await setup.runCommand("tmux new-session -d -s '\(name)'")
        #expect(created.termination == .exited(status: 0))

        await setup.requestPTY(cols: 100, rows: 30)
        let stream = try await setup.openShellChannel(command: "tmux attach-session -t '\(name)'")
        try await setup.write(Data("echo ATTACHED_$((40+2))\r".utf8))
        let output = try await Self.readUntil(stream: stream, containing: "ATTACHED_42")
        #expect(output.contains("ATTACHED_42"))
        await setup.disconnect()

        let cleanup = try await Self.connectWithPassword(deps)
        let listed = try await cleanup.runCommand("tmux list-sessions -F '#{session_name}'")
        #expect(listed.standardOutput.split(separator: "\n").contains(Substring(name)))
        _ = try await cleanup.runCommand("tmux kill-session -t '\(name)'")
        await cleanup.disconnect()
    }

    @Test(.tags(.integration), .enabled(if: RealSSHConnectionTests.serverReachable, "requires the docker SSH server with tmux (docker compose up -d)"))
    func discoverAndAttachThroughTmuxBackend() async throws {
        let deps = try Self.makeDeps()
        defer { Task { await deps.cleanup() } }
        let name = "tunlr disc '\(UUID().uuidString.prefix(6))'"

        let session = try await Self.connectWithPassword(deps)
        let backend = TmuxSessionBackend()
        let created = try await session.runCommand(try #require(backend.createCommand(name: name)))
        #expect(created.termination == .exited(status: 0))

        let entries = await RemoteSessionDiscovery().discover(using: session)
        let entry = try #require(entries.first { $0.backend == .tmux && $0.name == name })
        #expect(entry.detail.contains("1 window"))

        await session.requestPTY(cols: 90, rows: 30)
        await session.setShellCommand(entry.attachCommand)
        let stream = try await session.openShellChannel()
        try await session.write(Data("echo DISCOVERED_$((6*7))\r".utf8))
        let output = try await Self.readUntil(stream: stream, containing: "DISCOVERED_42")
        #expect(output.contains("DISCOVERED_42"))
        await session.disconnect()

        let cleanup = try await Self.connectWithPassword(deps)
        _ = try await cleanup.runCommand("tmux kill-session -t \(ShellQuote.quote(name))")
        await cleanup.disconnect()
    }
}

