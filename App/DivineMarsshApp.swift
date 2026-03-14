import SwiftUI

@main
struct DivineMarsshApp: App {
    private let profileStore: ProfileStore
    private let keyManager: KeyManager

    init() {
        let store = try! ProfileStore()
        self.profileStore = store
        let seManager = SecureEnclaveKeyManager()
        let kcManager = try! KeychainKeyManager()
        self.keyManager = KeyManager(secureEnclaveManager: seManager, keychainManager: kcManager)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(profileStore: profileStore, keyManager: keyManager)
        }
    }
}
