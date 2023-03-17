//
//  FurAffinityTests.swift
//  FurAffinityTests
//
//  Created by Ceylo on 17/03/2023.
//

import XCTest
@testable import Fur_Affinity

final class FAURLTests: XCTestCase {
    func testMatching() throws {
        let userUrl = URL(string: "https://www.furaffinity.net/user/xyz")!
        let submissionUrl = URL(string: "https://www.furaffinity.net/view/123/")!
        
        XCTAssertEqual(FAURL(with: userUrl), nil)
        XCTAssertEqual(FAURL(with: submissionUrl), .submission(url: submissionUrl))
    }
}
