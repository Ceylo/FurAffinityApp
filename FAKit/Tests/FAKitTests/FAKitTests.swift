import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import FAPages
@testable import FAKit

/// Serves canned pages and counts the requests per URL.
final class MockHTTPDataSource: HTTPDataSource, @unchecked Sendable {
    let dataForUrl: [URL: Data]
    private let lock = NSLock()
    private var counts = [URL: Int]()

    init(dataForUrl: [URL: Data] = [:]) {
        self.dataForUrl = dataForUrl
    }

    var requestCount: Int { lock.withLock { counts.values.reduce(0, +) } }
    func requestCount(for url: URL) -> Int { lock.withLock { counts[url, default: 0] } }

    func httpData(from url: URL, cookies: [HTTPCookie]?, method: HTTPMethod, parameters: [URLQueryItem]) async throws -> Data {
        lock.withLock { counts[url, default: 0] += 1 }
        return try dataForUrl[url].unwrap()
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
