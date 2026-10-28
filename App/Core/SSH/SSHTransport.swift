import Foundation
import CryptoKit
import Network
import NIOCore
@preconcurrency import NIOSSH
import NIOTransportServices

final class NIOSSHConnectionHandler: SSHConnectionHandling, @unchecked Sendable {
    static let timeout: TimeAmount = .seconds(10)

    private let hostKeyVerifier: HostKeyVerifier
    private let keyManager: KeyManager
    private let profileStore: ProfileStore

    init(hostKeyVerifier: HostKeyVerifier, keyManager: KeyManager, profileStore: ProfileStore) {
        self.hostKeyVerifier = hostKeyVerifier
        self.keyManager = keyManager
        self.profileStore = profileStore
    }

    func connect(profile: SSHConnectionProfile) async throws -> any SSHClientWrapping {
        let offer = try await resolveOffer(for: profile)
        let hostKeyDelegate = HostKeyValidatorAdapter(
            hostname: profile.host,
            port: profile.port,
            verifier: hostKeyVerifier
        )

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true

        let bootstrap = NIOTSConnectionBootstrap(group: NIOTSEventLoopGroup.singleton)
            .connectTimeout(Self.timeout)
            .tcpOptions(tcpOptions)
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    let configuration = SSHClientConfiguration(
                        userAuthDelegate: SingleOfferAuthDelegate(offer: offer),
                        serverAuthDelegate: hostKeyDelegate
                    )
                    try channel.pipeline.syncOperations.addHandlers(
                        NIOSSHHandler(
                            role: .client(configuration),
                            allocator: channel.allocator,
                            inboundChildChannelInitializer: nil
                        ),
                        AuthenticationHandler(eventLoop: channel.eventLoop, timeout: Self.timeout)
                    )
                }
            }

        let channel = try await bootstrap.connect(host: profile.host, port: Int(profile.port)).get()
        do {
            try await channel.pipeline.handler(type: AuthenticationHandler.self)
                .flatMap { $0.authenticated.futureResult }
                .get()
        } catch {
            channel.close(promise: nil)
            throw error
        }
        return NIOSSHClientConnection(channel: channel)
    }

    private func resolveOffer(for profile: SSHConnectionProfile) async throws -> NIOSSHUserAuthenticationOffer {
        switch profile.authMethod {
        case .secureEnclaveKey(let keyTag):
            let seKey = try await keyManager.secureEnclaveManager.loadKey(tag: keyTag)
            return Self.keyOffer(username: profile.username, key: NIOSSHPrivateKey(secureEnclaveP256Key: seKey))
        case .importedKey(let keyID):
            let rawData = try await keyManager.keychainManager.loadKey(id: keyID)
            let stored = try JSONDecoder().decode(StoredKeyData.self, from: rawData)
            return Self.keyOffer(username: profile.username, key: try Self.privateKey(from: stored))
        case .password:
            guard let password = await profileStore.password(for: profile.id) else {
                throw SSHSessionError.authenticationFailed
            }
            return NIOSSHUserAuthenticationOffer(
                username: profile.username,
                serviceName: "",
                offer: .password(.init(password: password))
            )
        }
    }

    private static func keyOffer(username: String, key: NIOSSHPrivateKey) -> NIOSSHUserAuthenticationOffer {
        NIOSSHUserAuthenticationOffer(
            username: username,
            serviceName: "",
            offer: .privateKey(.init(privateKey: key))
        )
    }

    private static func privateKey(from stored: StoredKeyData) throws -> NIOSSHPrivateKey {
        switch stored.keyType {
        case "ssh-ed25519":
            return NIOSSHPrivateKey(ed25519Key: try Curve25519.Signing.PrivateKey(rawRepresentation: stored.privateKeyBytes))
        case "ecdsa-sha2-nistp256":
            return NIOSSHPrivateKey(p256Key: try P256.Signing.PrivateKey(rawRepresentation: stored.privateKeyBytes))
        default:
            throw SSHSessionError.unsupportedKeyType(stored.keyType)
        }
    }
}

final class SingleOfferAuthDelegate: NIOSSHClientUserAuthenticationDelegate, @unchecked Sendable {
    private let offer: NIOSSHUserAuthenticationOffer
    private var offered = false

    init(offer: NIOSSHUserAuthenticationOffer) {
        self.offer = offer
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        guard !offered, availableMethods.contains(requiredMethod) else {
            nextChallengePromise.fail(SSHSessionError.authenticationFailed)
            return
        }
        offered = true
        nextChallengePromise.succeed(offer)
    }

    private var requiredMethod: NIOSSHAvailableUserAuthenticationMethods {
        switch offer.offer {
        case .password:
            .password
        default:
            .publicKey
        }
    }
}

final class AuthenticationHandler: ChannelInboundHandler, Sendable {
    typealias InboundIn = Any

    let authenticated: EventLoopPromise<Void>

    init(eventLoop: EventLoop, timeout: TimeAmount) {
        let promise = eventLoop.makePromise(of: Void.self)
        authenticated = promise
        eventLoop.scheduleTask(in: timeout) {
            promise.fail(ChannelError.connectTimeout(timeout))
        }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if event is UserAuthSuccessEvent {
            authenticated.succeed(())
        }
        context.fireUserInboundEventTriggered(event)
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        authenticated.fail(error)
        context.fireErrorCaught(error)
    }

    func channelInactive(context: ChannelHandlerContext) {
        authenticated.fail(ChannelError.ioOnClosedChannel)
        context.fireChannelInactive()
    }
}

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
        guard let publicKeyData = Self.wireRepresentation(of: hostKey) else {
            validationCompletePromise.fail(SSHSessionError.authenticationFailed)
            return
        }

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

    static func wireRepresentation(of hostKey: NIOSSHPublicKey) -> Data? {
        let fields = String(openSSHPublicKey: hostKey).split(separator: " ")
        guard fields.count >= 2 else { return nil }
        return Data(base64Encoded: String(fields[1]))
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

final class NIOSSHClientConnection: SSHClientWrapping, @unchecked Sendable {
    private let channel: Channel

    init(channel: Channel) {
        self.channel = channel
    }

    var isConnected: Bool {
        channel.isActive
    }

    func close() async throws {
        try await channel.close()
    }

    func onDisconnect(perform: @escaping @Sendable () -> Void) {
        channel.closeFuture.whenComplete { _ in perform() }
    }

    func openShell(
        pty: PTYConfiguration,
        onOutput: @escaping @Sendable (ShellOutput) -> Void,
        onEnd: @escaping @Sendable () -> Void
    ) async throws -> any SSHShellHandle {
        let parent = channel
        let ready = parent.eventLoop.makePromise(of: Void.self)
        let childChannel: Channel
        do {
            childChannel = try await parent.pipeline.handler(type: NIOSSHHandler.self).flatMap { sshHandler in
                let created = parent.eventLoop.makePromise(of: Channel.self)
                sshHandler.createChannel(created, channelType: .session) { child, _ in
                    child.eventLoop.makeCompletedFuture {
                        try child.pipeline.syncOperations.addHandler(
                            SessionChannelHandler(pty: pty, ready: ready, onOutput: onOutput, onEnd: onEnd)
                        )
                    }
                }
                return created.futureResult
            }.get()
            try await ready.futureResult.get()
        } catch {
            ready.fail(error)
            throw SSHSessionError.noActiveShell
        }
        return NIOSSHShellHandle(channel: childChannel)
    }
}

final class SessionChannelHandler: ChannelInboundHandler {
    typealias InboundIn = SSHChannelData

    private let pty: PTYConfiguration
    private let ready: EventLoopPromise<Void>
    private let onOutput: @Sendable (ShellOutput) -> Void
    private let onEnd: @Sendable () -> Void
    private var pendingReplies = 0

    init(
        pty: PTYConfiguration,
        ready: EventLoopPromise<Void>,
        onOutput: @escaping @Sendable (ShellOutput) -> Void,
        onEnd: @escaping @Sendable () -> Void
    ) {
        self.pty = pty
        self.ready = ready
        self.onOutput = onOutput
        self.onEnd = onEnd
    }

    func handlerAdded(context: ChannelHandlerContext) {
        context.channel.setOption(ChannelOptions.allowRemoteHalfClosure, value: true).whenFailure { [ready] error in
            ready.fail(error)
        }
    }

    func channelActive(context: ChannelHandlerContext) {
        let ptyRequest = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true,
            term: pty.term,
            terminalCharacterWidth: pty.cols,
            terminalRowHeight: pty.rows,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0,
            terminalModes: SSHTerminalModes([:])
        )
        pendingReplies = 2
        context.triggerUserOutboundEvent(ptyRequest, promise: nil)
        context.triggerUserOutboundEvent(SSHChannelRequestEvent.ShellRequest(wantReply: true), promise: nil)
        context.fireChannelActive()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let message = unwrapInboundIn(data)
        guard case .byteBuffer(let buffer) = message.data else { return }
        let bytes = Data(buffer.readableBytesView)
        switch message.type {
        case .stdErr:
            onOutput(.stderr(bytes))
        default:
            onOutput(.stdout(bytes))
        }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case is ChannelSuccessEvent:
            pendingReplies -= 1
            if pendingReplies == 0 {
                ready.succeed(())
            }
        case is ChannelFailureEvent:
            ready.fail(SSHSessionError.noActiveShell)
            context.close(promise: nil)
        default:
            context.fireUserInboundEventTriggered(event)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        ready.fail(error)
        context.close(promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        ready.fail(SSHSessionError.noActiveShell)
        onEnd()
        context.fireChannelInactive()
    }
}

final class NIOSSHShellHandle: SSHShellHandle, @unchecked Sendable {
    private let channel: Channel

    init(channel: Channel) {
        self.channel = channel
    }

    func write(_ data: Data) async throws {
        let buffer = channel.allocator.buffer(bytes: data)
        try await channel.writeAndFlush(SSHChannelData(type: .channel, data: .byteBuffer(buffer)))
    }

    func changeWindowSize(cols: Int, rows: Int) async throws {
        try await channel.triggerUserOutboundEvent(
            SSHChannelRequestEvent.WindowChangeRequest(
                terminalCharacterWidth: cols,
                terminalRowHeight: rows,
                terminalPixelWidth: 0,
                terminalPixelHeight: 0
            )
        ).get()
    }

    func cancel() {
        channel.close(promise: nil)
    }
}
