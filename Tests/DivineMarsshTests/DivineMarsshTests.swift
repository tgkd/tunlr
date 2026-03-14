import XCTest
@testable import DivineMarssh

final class DivineMarsshTests: XCTestCase {
    func testAppEntryPointExists() throws {
        let app = DivineMarsshApp()
        XCTAssertNotNil(app.body)
    }

    func testContentViewExists() throws {
        let view = ContentView()
        XCTAssertNotNil(view.body)
    }
}
