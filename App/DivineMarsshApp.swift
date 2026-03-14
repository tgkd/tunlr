import SwiftUI

@main
struct DivineMarsshApp: App {
    private let profileStore: ProfileStore
    private let keyManager: KeyManager
    @StateObject private var sessionManager: SSHSessionManager

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

        _sessionManager = StateObject(wrappedValue: SSHSessionManager(
            connectionHandlerFactory: {
                CitadelConnectionHandler(
                    hostKeyVerifier: hostKeyVerifier,
                    keyManager: km,
                    profileStore: store
                )
            },
            profileStore: store
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                profileStore: profileStore,
                keyManager: keyManager,
                sessionManager: sessionManager
            )
        }
    }
}
