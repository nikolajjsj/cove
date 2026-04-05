import XCTest

@testable import Persistence

final class PersistenceTests: XCTestCase {
    func testDatabaseManagerInitialization() {
        let manager = DatabaseManager()
        XCTAssertNotNil(manager)
    }
}
