//
//  FASubmissionsPageTests.swift
//  
//
//  Created by Ceylo on 17/10/2021.
//

import XCTest
@testable import FAPages

final class FANotificationsPageTests: XCTestCase {
    func testShoutOnly_returnsNoJournal() async throws {
        let data = testData("www.furaffinity.net:msg:others-shout-only.html")
        let page = await FANotificationsPage(data: data)
        XCTAssertNotNil(page)
        XCTAssertEqual([], page!.submissionCommentHeaders)
        XCTAssertEqual([], page!.journalHeaders)
    }
    
    func testEmpty_returnsNoJournal() async throws {
        let data = testData("www.furaffinity.net:msg:others-empty.html")
        let page = await FANotificationsPage(data: data)
        XCTAssertNotNil(page)
        XCTAssertEqual([], page!.submissionCommentHeaders)
        XCTAssertEqual([], page!.journalHeaders)
    }
    
    func testPageContainsJournals_listsJournals() async throws {
        let data = testData("www.furaffinity.net:msg:others-journals-only.html")
        let page = await FANotificationsPage(data: data)
        XCTAssertNotNil(page)
        
        let expected: [FANotificationsPage.Header] = [
            .init(id: 10526001, author: "holt-odium", displayAuthor: "Holt-Odium", title: "📝 3 Slots are available",
                  datetime: "on Apr 14, 2023 08:23 PM", naturalDatetime: "18 hours ago",
                  url: URL(string: "https://www.furaffinity.net/journal/10526001/")!),
            .init(id: 10521084, author: "holt-odium", displayAuthor: "Holt-Odium", title: "Sketch commission are open (115$)",
                  datetime: "on Apr 8, 2023 07:00 PM", naturalDatetime: "a week ago",
                  url: URL(string: "https://www.furaffinity.net/journal/10521084/")!),
            .init(id: 10516170, author: "rudragon", displayAuthor: "RUdragon", title: "UPGRADES ARE OPEN!!! 5",
                  datetime: "on Apr 2, 2023 11:59 PM", naturalDatetime: "12 days ago",
                  url: URL(string: "https://www.furaffinity.net/journal/10516170/")!),
            .init(id: 10512063, author: "ishiru", displayAuthor: "Ishiru", title: "30 minutes before end of auction",
                  datetime: "on Mar 29, 2023 03:33 PM", naturalDatetime: "17 days ago",
                  url: URL(string: "https://www.furaffinity.net/journal/10512063/")!),
            .init(id: 10511753, author: "ishiru", displayAuthor: "Ishiru", title: "one day left",
                  datetime: "on Mar 29, 2023 07:42 AM", naturalDatetime: "17 days ago",
                  url: URL(string: "https://www.furaffinity.net/journal/10511753/")!)
        ]
        XCTAssertEqual([], page!.submissionCommentHeaders)
        XCTAssertEqual(expected, page!.journalHeaders)
    }
    
    func testPageContainsSubmissionComments_listsComments() async throws {
        let data = testData("www.furaffinity.net:msg:others-submission-comments-only.html")
        let page = await FANotificationsPage(data: data)
        XCTAssertNotNil(page)
        
        let expected: [FANotificationsPage.Header] = [
            .init(id: 172177443, author: "furrycount", displayAuthor: "Furrycount", title: "FurAffinity iOS App 1.3 Update",
                  datetime: "on Apr 30, 2023 09:50 PM", naturalDatetime: "a few seconds ago",
                  url: URL(string: "https://www.furaffinity.net/view/49215481/#cid:172177443")!),
            .init(id: 172177425, author: "furrycount", displayAuthor: "Furrycount", title: "FurAffinity iOS App 1.3 Update",
                  datetime: "on Apr 30, 2023 09:49 PM", naturalDatetime: "a minute ago",
                  url: URL(string: "https://www.furaffinity.net/view/49215481/#cid:172177425")!)
        ]
        XCTAssertEqual(expected, page!.submissionCommentHeaders)
        XCTAssertEqual([], page!.journalHeaders)
    }
}
