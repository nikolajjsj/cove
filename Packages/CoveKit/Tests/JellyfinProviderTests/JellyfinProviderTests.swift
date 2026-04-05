import XCTest

@testable import JellyfinProvider

final class JellyfinProviderTests: XCTestCase {
    func testJellyfinServerProviderInitializes() {
        let provider = JellyfinServerProvider()
        XCTAssertNotNil(provider)
    }
}
