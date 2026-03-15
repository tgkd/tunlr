import SwiftUI

@main
struct DivineMarsshApp: App {
    private let profileStore: ProfileStore
    private let keyManager: KeyManager
    @StateObject private var sessionManager: SSHSessionManager
    @StateObject private var appearanceViewModel: AppearanceViewModel

    init() {
        let store = try! ProfileStore()
        self.profileStore = store
        let seManager = SecureEnclaveKeyManager()
        let kcManager = try! KeychainKeyManager()
        let km = KeyManager(secureEnclaveManager: seManager, keychainManager: kcManager)
        self.keyManager = km

        let knownHostsStore = try! KnownHostsStore()
        let hostKeyVerifier = HostKeyVerifier(
            store: knownHostsStore,
            approvalHandler: { _ in true }
        )

        let terminalStateCache = try! TerminalStateCache()

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

        let appearanceStore = try! AppearanceStore()
        _appearanceViewModel = StateObject(wrappedValue: AppearanceViewModel(store: appearanceStore))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                profileStore: profileStore,
                keyManager: keyManager,
                sessionManager: sessionManager,
                appearanceViewModel: appearanceViewModel
            )
            .task {
                await sessionManager.checkForRestoredSession()
                await appearanceViewModel.load()
            }
        }
    }
}
