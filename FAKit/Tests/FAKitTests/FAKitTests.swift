import XCTest
import FAPages
@testable import FAKit

struct MockHTTPDataSource: HTTPDataSource {
    var dataForUrl = [URL : Data]()
    
    func httpData(from url: URL) async -> Data? {
        dataForUrl[url]
    }
}

final class FAKitTests: XCTestCase {
    func testExample() async throws {
        let mock = MockHTTPDataSource(dataForUrl: [
            FAHomePage.url: testData("www.furaffinity.net-loggedout.html")
        ])
        
        let session = await FASession(cookies: [], dataSource: mock)
        XCTAssertNil(session)
    }
}
