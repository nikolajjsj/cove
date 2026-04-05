import XCTest

@testable import DownloadManager

final class DownloadManagerTests: XCTestCase {
    func testDownloadManagerServiceInitializes() {
        let manager = DownloadManagerService()
        XCTAssertNotNil(manager)
    }
}
