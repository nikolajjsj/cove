import XCTest

@testable import JellyfinAPI

final class JellyfinAPITests: XCTestCase {
    func testJellyfinAPIClientInitialization() {
        let client = JellyfinAPIClient()
        XCTAssertNotNil(client)
    }
}
