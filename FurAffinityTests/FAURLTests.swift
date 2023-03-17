//
//  FurAffinityTests.swift
//  FurAffinityTests
//
//  Created by Ceylo on 17/03/2023.
//

import XCTest
@testable import Fur_Affinity

final class FAURLTests: XCTestCase {
    func testNotMatching() throws {
        let userUrl = URL(string: "https://www.furaffinity.net/user/xyz")!
        XCTAssertEqual(FAURL(with: userUrl), nil)
    }
    
    func testMatchingSubmission() {
        let submissionUrl = URL(string: "https://www.furaffinity.net/view/123/")!
        XCTAssertEqual(FAURL(with: submissionUrl), .submission(url: submissionUrl))
    }
    
    func testMatchingNote() {
        let noteUrl = URL(string: "https://www.furaffinity.net/msg/pms/1/234/#message")!
        XCTAssertEqual(FAURL(with: noteUrl), .note(url: noteUrl))
    }
}
