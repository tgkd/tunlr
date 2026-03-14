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

    private struct TestDeps {
        let hostKeyVerifier: HostKeyVerifier
        let keyManager: KeyManager
        let profileStore: ProfileStore
        let tempDir: URL
        let keychainServiceName: String

        func cleanup() async {
            let allKeys = await keyManager.listAllKeys()
            for key in allKeys {
                await keyManager.deleteKey(identity: key)
            }
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    private static func makeDeps(
        approvalHandler: @escaping @Sendable (HostKeyVerificationRequest) async -> Bool = { _ in true }
    ) throws -> TestDeps {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RealSSHTest-\(UUID().uuidString)")

        let knownHostsStore = try KnownHostsStore(
            directory: tempDir.appendingPathComponent("hosts")
        )
        let hostKeyVerifier = HostKeyVerifier(
            store: knownHostsStore,
            approvalHandler: approvalHandler
        )

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
            keyManager: keyManager,
            profileStore: profileStore,
            tempDir: tempDir,
            keychainServiceName: keychainServiceName
        )
    }

    private static func makeHandler(_ deps: TestDeps) -> CitadelConnectionHandler {
        CitadelConnectionHandler(
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

    @Test(.tags(.integration))
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

    @Test(.tags(.integration))
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

    @Test(.tags(.integration))
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

    @Test(.tags(.integration))
    func hostKeyTOFUFlow() async throws {
        let approvalCount = ApprovalCounter()

        let deps = try Self.makeDeps { _ in
            await approvalCount.increment()
            return true
        }
        defer { Task { await deps.cleanup() } }

        let profile = SSHConnectionProfile(
            host: Self.host, port: Self.port,
            username: Self.username, authMethod: .password
        )
        try await deps.profileStore.addProfile(profile, password: Self.password)

        let handler = Self.makeHandler(deps)

        let session1 = SSHSession(connectionHandler: handler)
        try await session1.connect(profile: profile)
        let count1 = await approvalCount.count
        #expect(count1 == 1)
        await session1.disconnect()

        let session2 = SSHSession(connectionHandler: handler)
        try await session2.connect(profile: profile)
        let count2 = await approvalCount.count
        #expect(count2 == 1)
        await session2.disconnect()
    }

    // MARK: - Wrong Password

    @Test(.tags(.integration))
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

    @Test(.tags(.integration))
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
}

private actor ApprovalCounter {
    var count = 0

    func increment() {
        count += 1
    }
}
