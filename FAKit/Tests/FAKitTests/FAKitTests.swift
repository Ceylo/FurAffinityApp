import Testing
import Foundation
import FAPages
@testable import FAKit

struct MockHTTPDataSource: HTTPDataSource {
    var dataForUrl = [URL : Data]()

    func httpData(from url: URL, cookies: [HTTPCookie]?, method: HTTPMethod, parameters: [URLQueryItem]) async throws -> Data {
        try dataForUrl[url].unwrap()
    }
}

struct FAKitTests {
    @Test
    func loggedOut() async throws {
        let mock = MockHTTPDataSource(dataForUrl: [
            FAURLs.homeUrl: testData("www.furaffinity.net:loggedout.html")
        ])

        let session = try await OnlineFASession(cookies: [], dataSource: mock)
        #expect(session == nil)
    }
}
