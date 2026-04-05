import XCTest

@testable import PlaybackEngine

final class PlaybackEngineTests: XCTestCase {
    func testPlaybackEngineModuleVersion() {
        XCTAssertEqual(PlaybackEngineModule.version, "1.0.0")
    }
}
