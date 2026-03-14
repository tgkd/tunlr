import XCTest
@testable import DivineMarssh

final class DivineMarsshTests: XCTestCase {
    @MainActor
    func testAppEntryPointExists() throws {
        let app = DivineMarsshApp()
        XCTAssertNotNil(app.body)
    }

    @MainActor
    func testContentViewExists() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try ProfileStore(directory: dir)
        let seManager = SecureEnclaveKeyManager()
        let kcManager = try KeychainKeyManager()
        let keyManager = KeyManager(secureEnclaveManager: seManager, keychainManager: kcManager)
        let view = ContentView(profileStore: store, keyManager: keyManager)
        XCTAssertNotNil(view.body)
    }
}
