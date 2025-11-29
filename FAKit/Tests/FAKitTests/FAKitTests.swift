import XCTest
import FAPages
@testable import FAKit

struct MockHTTPDataSource: HTTPDataSource {
    var dataForUrl = [URL : Data]()
    
    func httpData(from url: URL, cookies: [HTTPCookie]?, method: HTTPMethod, parameters: [URLQueryItem]) async throws -> Data {
        try dataForUrl[url].unwrap()
    }
}

final class FAKitTests: XCTestCase {
    func testLoggedOut() async throws {
        let mock = MockHTTPDataSource(dataForUrl: [
            FAURLs.homeUrl: testData("www.furaffinity.net:loggedout.html")
        ])
        
        let session = await OnlineFASession(cookies: [], dataSource: mock)
        XCTAssertNil(session)
    }
}
