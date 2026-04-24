import SwiftUI

@main
struct DivineMarsshApp: App {
    private let profileStore: ProfileStore
    private let keyManager: KeyManager
    @StateObject private var sessionManager: SSHSessionManager
    @StateObject private var appearanceViewModel: AppearanceViewModel

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

        let hostKeyVerifier = HostKeyVerifier(store: knownHostsStore)

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
