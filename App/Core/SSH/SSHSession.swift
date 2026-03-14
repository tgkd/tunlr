import Foundation
@preconcurrency import Citadel
import NIOCore
@preconcurrency import NIOSSH
import CryptoKit

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
        self.connectionHandler = CitadelConnectionHandler(
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
        } catch {
            updateState(.disconnected)
            throw error
        }
    }

    func disconnect() async {
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

    private func handleUnexpectedDisconnect() {
        client = nil
        shellHandle = nil
        updateState(.disconnected)
    }

    private func handleShellEnded() {
        shellHandle = nil
    }
}

// MARK: - Citadel Integration

final class CitadelConnectionHandler: SSHConnectionHandling, @unchecked Sendable {
    private let hostKeyVerifier: HostKeyVerifier
    private let keyManager: KeyManager
    private let profileStore: ProfileStore

    init(hostKeyVerifier: HostKeyVerifier, keyManager: KeyManager, profileStore: ProfileStore) {
        self.hostKeyVerifier = hostKeyVerifier
        self.keyManager = keyManager
        self.profileStore = profileStore
    }

    func connect(profile: SSHConnectionProfile) async throws -> any SSHClientWrapping {
        let authMethod = try await resolveAuthMethod(for: profile)
        let hostValidator = makeHostKeyValidator(hostname: profile.host, port: profile.port)

        var settings = SSHClientSettings(
            host: profile.host,
            port: Int(profile.port),
            authenticationMethod: { authMethod },
            hostKeyValidator: hostValidator
        )
        settings.connectTimeout = .seconds(10)
        settings.algorithms = AlgorithmPolicy.makeSecureAlgorithms()

        let client = try await SSHClient.connect(to: settings)
        return CitadelClientWrapper(client: client)
    }

    private func resolveAuthMethod(for profile: SSHConnectionProfile) async throws -> SSHAuthenticationMethod {
        switch profile.authMethod {
        case .secureEnclaveKey(let keyTag):
            let seKey = try await keyManager.secureEnclaveManager.loadKey(tag: keyTag)
            let sshKey = NIOSSHPrivateKey(custom: SecureEnclaveP256SSHKey(seKey: seKey))
            return .custom(
                SEAuthDelegate(username: profile.username, privateKey: sshKey)
            )
        case .importedKey(let keyID):
            let rawData = try await keyManager.keychainManager.loadKey(id: keyID)
            let stored = try JSONDecoder().decode(StoredKeyData.self, from: rawData)
            return try buildAuthMethod(username: profile.username, stored: stored)
        case .password:
            let password = await profileStore.password(for: profile.id) ?? ""
            defer {
                // Password string is short-lived; log nothing about it
                _ = MemoryHygiene.sanitize(password, label: "PASSWORD")
            }
            return .passwordBased(username: profile.username, password: password)
        }
    }

    private func buildAuthMethod(
        username: String,
        stored: StoredKeyData
    ) throws -> SSHAuthenticationMethod {
        switch stored.keyType {
        case "ssh-ed25519":
            let key = try Curve25519.Signing.PrivateKey(rawRepresentation: stored.privateKeyBytes)
            return .ed25519(username: username, privateKey: key)
        case "ecdsa-sha2-nistp256":
            let key = try P256.Signing.PrivateKey(rawRepresentation: stored.privateKeyBytes)
            return .p256(username: username, privateKey: key)
        default:
            throw SSHSessionError.unsupportedKeyType(stored.keyType)
        }
    }

    private func makeHostKeyValidator(hostname: String, port: UInt16) -> SSHHostKeyValidator {
        let verifier = hostKeyVerifier
        let adapter = HostKeyValidatorAdapter(
            hostname: hostname,
            port: port,
            verifier: verifier
        )
        return .custom(adapter)
    }
}

// MARK: - SE Auth Delegate

final class SEAuthDelegate: NIOSSHClientUserAuthenticationDelegate, @unchecked Sendable {
    private let username: String
    private let privateKey: NIOSSHPrivateKey

    init(username: String, privateKey: NIOSSHPrivateKey) {
        self.username = username
        self.privateKey = privateKey
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        guard availableMethods.contains(.publicKey) else {
            nextChallengePromise.fail(SSHSessionError.authenticationFailed)
            return
        }
        nextChallengePromise.succeed(NIOSSHUserAuthenticationOffer(
            username: username,
            serviceName: "",
            offer: .privateKey(.init(privateKey: privateKey))
        ))
    }
}

// MARK: - Secure Enclave P-256 SSH Key

struct SecureEnclaveP256SSHKey: NIOSSHPrivateKeyProtocol {
    static let keyPrefix = "ecdsa-sha2-nistp256"

    let seKey: SecureEnclave.P256.Signing.PrivateKey

    var publicKey: NIOSSHPublicKeyProtocol {
        SecureEnclaveP256PublicSSHKey(key: seKey.publicKey)
    }

    func signature<D: DataProtocol>(for data: D) throws -> NIOSSHSignatureProtocol {
        let sig = try seKey.signature(for: data)
        return ECDSAP256SSHSignature(rawP1363: sig.rawRepresentation)
    }
}

struct SecureEnclaveP256PublicSSHKey: NIOSSHPublicKeyProtocol {
    static let publicKeyPrefix = "ecdsa-sha2-nistp256"

    let key: P256.Signing.PublicKey

    var rawRepresentation: Data { key.x963Representation }

    func isValidSignature<D: DataProtocol>(_ signature: NIOSSHSignatureProtocol, for data: D) -> Bool {
        guard let ecdsaSig = signature as? ECDSAP256SSHSignature,
              let sig = try? P256.Signing.ECDSASignature(rawRepresentation: ecdsaSig.rawP1363) else {
            return false
        }
        return key.isValidSignature(sig, for: data)
    }

    func write(to buffer: inout ByteBuffer) -> Int {
        var written = 0
        let curve = Array("nistp256".utf8)
        written += buffer.writeInteger(UInt32(curve.count))
        written += buffer.writeBytes(curve)
        let point = Array(key.x963Representation)
        written += buffer.writeInteger(UInt32(point.count))
        written += buffer.writeBytes(point)
        return written
    }

    static func read(from buffer: inout ByteBuffer) throws -> Self {
        guard let curveLen = buffer.readInteger(as: UInt32.self),
              let _ = buffer.readSlice(length: Int(curveLen)),
              let pointLen = buffer.readInteger(as: UInt32.self),
              let pointBytes = buffer.readBytes(length: Int(pointLen)) else {
            throw SSHSessionError.authenticationFailed
        }
        let key = try P256.Signing.PublicKey(x963Representation: pointBytes)
        return Self(key: key)
    }
}

struct ECDSAP256SSHSignature: NIOSSHSignatureProtocol {
    static let signaturePrefix = "ecdsa-sha2-nistp256"

    let rawP1363: Data

    var rawRepresentation: Data { rawP1363 }

    func write(to buffer: inout ByteBuffer) -> Int {
        let r = Array(rawP1363.prefix(32))
        let s = Array(rawP1363.dropFirst(32))

        var inner = ByteBuffer()
        var innerLen = 0
        innerLen += writePositiveMPInt(r, to: &inner)
        innerLen += writePositiveMPInt(s, to: &inner)

        var written = 0
        written += buffer.writeInteger(UInt32(innerLen))
        written += buffer.writeBuffer(&inner)
        return written
    }

    static func read(from buffer: inout ByteBuffer) throws -> Self {
        guard let blobLen = buffer.readInteger(as: UInt32.self),
              var blob = buffer.readSlice(length: Int(blobLen)) else {
            throw SSHSessionError.authenticationFailed
        }
        guard let rLen = blob.readInteger(as: UInt32.self),
              var rBytes = blob.readBytes(length: Int(rLen)),
              let sLen = blob.readInteger(as: UInt32.self),
              var sBytes = blob.readBytes(length: Int(sLen)) else {
            throw SSHSessionError.authenticationFailed
        }
        while rBytes.count > 32 && rBytes.first == 0 { rBytes.removeFirst() }
        while sBytes.count > 32 && sBytes.first == 0 { sBytes.removeFirst() }
        while rBytes.count < 32 { rBytes.insert(0, at: 0) }
        while sBytes.count < 32 { sBytes.insert(0, at: 0) }
        return Self(rawP1363: Data(rBytes + sBytes))
    }

    private func writePositiveMPInt(_ bytes: [UInt8], to buffer: inout ByteBuffer) -> Int {
        var b = bytes
        while b.count > 1 && b.first == 0 { b.removeFirst() }
        let needsPadding = (b.first ?? 0) & 0x80 != 0
        let totalLen = b.count + (needsPadding ? 1 : 0)
        var written = 0
        written += buffer.writeInteger(UInt32(totalLen))
        if needsPadding {
            written += buffer.writeInteger(UInt8(0))
        }
        written += buffer.writeBytes(b)
        return written
    }
}

// MARK: - Host Key Validator Adapter

final class HostKeyValidatorAdapter: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    private let hostname: String
    private let port: UInt16
    private let verifier: HostKeyVerifier

    init(hostname: String, port: UInt16, verifier: HostKeyVerifier) {
        self.hostname = hostname
        self.port = port
        self.verifier = verifier
    }

    func validateHostKey(
        hostKey: NIOSSHPublicKey,
        validationCompletePromise: EventLoopPromise<Void>
    ) {
        var buffer = ByteBuffer()
        _ = hostKey.write(to: &buffer)
        let publicKeyData = Data(buffer.readableBytesView)

        let keyType = Self.extractKeyType(from: publicKeyData)

        let verifier = self.verifier
        let hostname = self.hostname
        let port = self.port

        Task {
            do {
                try await verifier.verify(
                    hostname: hostname,
                    port: port,
                    keyType: keyType,
                    publicKeyData: publicKeyData
                )
                validationCompletePromise.succeed(())
            } catch {
                validationCompletePromise.fail(error)
            }
        }
    }

    static func extractKeyType(from publicKeyData: Data) -> String {
        guard publicKeyData.count >= 4 else { return "unknown" }
        let length = Int(publicKeyData[0]) << 24
            | Int(publicKeyData[1]) << 16
            | Int(publicKeyData[2]) << 8
            | Int(publicKeyData[3])
        guard publicKeyData.count >= 4 + length else { return "unknown" }
        let typeBytes = publicKeyData[4..<(4 + length)]
        return String(data: Data(typeBytes), encoding: .utf8) ?? "unknown"
    }
}

// MARK: - Citadel Client Wrapper

private final class WriterBox: @unchecked Sendable {
    var writer: TTYStdinWriter?
}

final class CitadelClientWrapper: SSHClientWrapping, @unchecked Sendable {
    private let client: SSHClient

    init(client: SSHClient) {
        self.client = client
    }

    var isConnected: Bool {
        client.isConnected
    }

    func close() async throws {
        try await client.close()
    }

    func onDisconnect(perform: @escaping @Sendable () -> Void) {
        client.onDisconnect(perform: perform)
    }

    func openShell(
        pty: PTYConfiguration,
        onOutput: @escaping @Sendable (ShellOutput) -> Void,
        onEnd: @escaping @Sendable () -> Void
    ) async throws -> any SSHShellHandle {
        let ptyRequest = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true,
            term: pty.term,
            terminalCharacterWidth: pty.cols,
            terminalRowHeight: pty.rows,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0,
            terminalModes: SSHTerminalModes([:])
        )

        let writerBox = WriterBox()
        let (readyStream, readyContinuation) = AsyncStream.makeStream(of: Bool.self)

        let shellTask = Task {
            do {
                try await client.withPTY(ptyRequest) { output, writer in
                    writerBox.writer = writer
                    readyContinuation.yield(true)
                    readyContinuation.finish()

                    for try await chunk in output {
                        switch chunk {
                        case .stdout(let buffer):
                            onOutput(.stdout(Data(buffer.readableBytesView)))
                        case .stderr(let buffer):
                            onOutput(.stderr(Data(buffer.readableBytesView)))
                        }
                    }
                }
            } catch {
                readyContinuation.yield(false)
                readyContinuation.finish()
            }
            onEnd()
        }

        var ready = false
        for await success in readyStream {
            ready = success
            break
        }

        guard ready, let writer = writerBox.writer else {
            shellTask.cancel()
            throw SSHSessionError.noActiveShell
        }

        return CitadelShellHandle(writer: writer, task: shellTask)
    }
}

final class CitadelShellHandle: SSHShellHandle, @unchecked Sendable {
    private let writer: TTYStdinWriter
    private let task: Task<Void, Never>

    init(writer: TTYStdinWriter, task: Task<Void, Never>) {
        self.writer = writer
        self.task = task
    }

    func write(_ data: Data) async throws {
        try await writer.write(ByteBuffer(data: data))
    }

    func changeWindowSize(cols: Int, rows: Int) async throws {
        try await writer.changeSize(cols: cols, rows: rows, pixelWidth: 0, pixelHeight: 0)
    }

    func cancel() {
        task.cancel()
    }
}
