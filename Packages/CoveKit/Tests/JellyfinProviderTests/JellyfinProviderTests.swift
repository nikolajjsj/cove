import XCTest

@testable import JellyfinProvider

final class JellyfinProviderTests: XCTestCase {
    func testProviderInitialization() {
        let provider = JellyfinServerProvider()
        XCTAssertNotNil(provider)
    }

    func testDisconnectDoesNotCrashWhenNotConnected() async {
        let provider = JellyfinServerProvider()
        await provider.disconnect()  // Should not crash
    }
}
