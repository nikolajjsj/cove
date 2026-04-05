import XCTest

@testable import PlaybackEngine

final class PlaybackEngineTests: XCTestCase {
    func testPlaybackEngineModuleVersion() {
        XCTAssertEqual(PlaybackEngineModule.version, "0.1.0")
    }
}
