import XCTest
@testable import FAKit

final class FAKitTests: XCTestCase {
    func testExample() throws {
        Task {
            let session = await FASession(cookies: [])
            XCTAssertNil(session)
        }
    }
}
