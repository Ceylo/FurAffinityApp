//
//  FurAffinityTests.swift
//  FurAffinityTests
//
//  Created by Ceylo on 17/03/2023.
//

import XCTest
@testable import Fur_Affinity

final class FATargetTests: XCTestCase {
    func testNotMatching() {
        let url = URL(string: "https://www.patreon.com/")!
        XCTAssertEqual(FATarget(with: url), nil)
    }
    
    func testMatchingUser() {
        let userUrl = URL(string: "https://www.furaffinity.net/user/xyz")!
        XCTAssertEqual(FATarget(with: userUrl), .user(url: userUrl, previewData: nil))
    }
    
    func testMatchingSubmission() {
        let submissionUrl = URL(string: "https://www.furaffinity.net/view/123/")!
        XCTAssertEqual(FATarget(with: submissionUrl), .submission(url: submissionUrl, previewData: nil))
    }
    
    func testMatchingNote() {
        let noteUrl = URL(string: "https://www.furaffinity.net/msg/pms/1/234/#message")!
        XCTAssertEqual(FATarget(with: noteUrl), .note(url: noteUrl))
    }
    
    func testMatchingJournal() {
        let journalUrl = URL(string: "https://www.furaffinity.net/journal/10516170/")!
        XCTAssertEqual(FATarget(with: journalUrl), .journal(url: journalUrl))
    }
}
