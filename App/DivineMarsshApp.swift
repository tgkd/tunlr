import SwiftUI

@MainActor
final class HostKeyApprovalCoordinator: ObservableObject {
    @Published var pendingRequest: HostKeyVerificationRequest?
    private var continuation: CheckedContinuation<Bool, Never>?

    func approve(_ request: HostKeyVerificationRequest) async -> Bool {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.pendingRequest = request
        }
    }

    func userTrusted() {
        continuation?.resume(returning: true)
        continuation = nil
        pendingRequest = nil
    }

    func userRejected() {
        continuation?.resume(returning: false)
        continuation = nil
        pendingRequest = nil
    }
}

@main
struct DivineMarsshApp: App {
    private let profileStore: ProfileStore
    private let keyManager: KeyManager
    @StateObject private var sessionManager: SSHSessionManager
    @StateObject private var appearanceViewModel: AppearanceViewModel
    @StateObject private var approvalCoordinator = HostKeyApprovalCoordinator()

    init() {
        let store: ProfileStore
        let kcManager: KeychainKeyManager
        let knownHostsStore: KnownHostsStore
        let terminalStateCache: TerminalStateCache

        do {
            store = try ProfileStore()
            kcManager = try KeychainKeyManager()
            knownHostsStore = try KnownHostsStore()
            terminalStateCache = try TerminalStateCache()
        } catch {
            fatalError("Failed to initialize app storage: \(error.localizedDescription)")
        }

        self.profileStore = store
        let seManager = SecureEnclaveKeyManager()
        let km = KeyManager(secureEnclaveManager: seManager, keychainManager: kcManager)
        self.keyManager = km

        let coordinator = HostKeyApprovalCoordinator()
        let hostKeyVerifier = HostKeyVerifier(
            store: knownHostsStore,
            approvalHandler: { request in
                await coordinator.approve(request)
            }
        )

        _sessionManager = StateObject(wrappedValue: SSHSessionManager(
            connectionHandlerFactory: {
                CitadelConnectionHandler(
                    hostKeyVerifier: hostKeyVerifier,
                    keyManager: km,
                    profileStore: store
                )
            },
            profileStore: store,
            terminalStateCache: terminalStateCache
        ))

        let appearanceStore: AppearanceStore
        do {
            appearanceStore = try AppearanceStore()
        } catch {
            fatalError("Failed to initialize appearance storage: \(error.localizedDescription)")
        }
        _appearanceViewModel = StateObject(wrappedValue: AppearanceViewModel(store: appearanceStore))
        _approvalCoordinator = StateObject(wrappedValue: coordinator)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                profileStore: profileStore,
                keyManager: keyManager,
                sessionManager: sessionManager,
                appearanceViewModel: appearanceViewModel,
                approvalCoordinator: approvalCoordinator
            )
            .task {
                await sessionManager.checkForRestoredSession()
                await appearanceViewModel.load()
            }
        }
    }
}
