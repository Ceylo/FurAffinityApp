//
//  FurAffinityTests.swift
//  FurAffinityTests
//
//  Created by Ceylo on 17/03/2023.
//

import XCTest
@testable import Fur_Affinity

final class FAURLTests: XCTestCase {
    func testNotMatching() {
        let url = URL(string: "https://www.patreon.com/")!
        XCTAssertEqual(FAURL(with: url), nil)
    }
    
    func testMatchingUser() {
        let userUrl = URL(string: "https://www.furaffinity.net/user/xyz")!
        XCTAssertEqual(FAURL(with: userUrl), .user(url: userUrl))
    }
    
    func testMatchingSubmission() {
        let submissionUrl = URL(string: "https://www.furaffinity.net/view/123/")!
        XCTAssertEqual(FAURL(with: submissionUrl), .submission(url: submissionUrl, previewData: nil))
    }
    
    func testMatchingNote() {
        let noteUrl = URL(string: "https://www.furaffinity.net/msg/pms/1/234/#message")!
        XCTAssertEqual(FAURL(with: noteUrl), .note(url: noteUrl))
    }
    
    func testMatchingJournal() {
        let journalUrl = URL(string: "https://www.furaffinity.net/journal/10516170/")!
        XCTAssertEqual(FAURL(with: journalUrl), .journal(url: journalUrl))
    }
}
