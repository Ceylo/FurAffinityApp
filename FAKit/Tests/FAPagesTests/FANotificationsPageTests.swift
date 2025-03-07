//
//  FASubmissionsPageTests.swift
//  
//
//  Created by Ceylo on 17/10/2021.
//

import XCTest
@testable import FAPages

final class FANotificationsPageTests: XCTestCase {
    func testShoutOnly_returnsShout() async throws {
        let data = testData("www.furaffinity.net:msg:others-comments-journals-shout.html")
        let page = try await FANotificationsPage(data: data).unwrap()
        XCTAssertEqual(page.submissionCommentHeaders, [
            .init(
                id: 183695893,
                author: "someuser",
                displayAuthor: "SomeUser",
                title: "FurAffinity iOS App 1.3 Update",
                datetime: "Jan 17, 2025 10:11 PM",
                naturalDatetime: "a month ago",
                url: URL(string: "https://www.furaffinity.net/view/49215481/#cid:183695893")!
            )
        ])
        XCTAssertEqual(page.journalCommentHeaders, [
            .init(
                id: 60980385,
                author: "someuser",
                displayAuthor: "SomeUser",
                title: "Test",
                datetime: "Mar 4, 2025 11:23 PM",
                naturalDatetime: "a minute ago",
                url: URL(string: "https://www.furaffinity.net/journal/10528107/#cid:60980385")!
            )
        ])
        
        XCTAssertEqual(page.shoutHeaders, [
            .init(
                id: 56046409, author: "someuser", displayAuthor: "SomeUser", title: "",
                datetime: "on Dec 23, 2024 05:56 PM", naturalDatetime: "2 months ago",
                url: URL(string: "https://www.furaffinity.net/user/furrycount#shout-56046409")!
            )
        ])
        
        XCTAssertEqual(page.journalHeaders.count, 21)
        XCTAssertEqual(page.journalHeaders.prefix(3), [
            .init(
                id: 11084927,
                author: "leilryu",
                displayAuthor: "leilryu",
                title: "Commissions are open!",
                datetime: "Mar 3, 2025 10:41 PM",
                naturalDatetime: "a day ago",
                url: URL(string: "https://www.furaffinity.net/journal/11084927/")!
            ),
            .init(
                id: 11064320,
                author: "leilryu",
                displayAuthor: "leilryu",
                title: "[closed]",
                datetime: "Feb 3, 2025 09:51 PM",
                naturalDatetime: "a month ago",
                url: URL(string: "https://www.furaffinity.net/journal/11064320/")!
            ),
            .init(
                id: 11049380,
                author: "ishiru",
                displayAuthor: "Ishiru",
                title: "YCH ends this evening",
                datetime: "Jan 14, 2025 07:36 PM",
                naturalDatetime: "a month ago",
                url: URL(string: "https://www.furaffinity.net/journal/11049380/")!
            )
        ])
    }
    
    func testEmpty_returnsNoJournal() async throws {
        let data = testData("www.furaffinity.net:msg:others-empty.html")
        let page = try await FANotificationsPage(data: data).unwrap()
        XCTAssertEqual([], page.submissionCommentHeaders)
        XCTAssertEqual([], page.journalCommentHeaders)
        XCTAssertEqual([], page.journalHeaders)
    }
    
    func testPageContainsJournals_listsJournals() async throws {
        let data = testData("www.furaffinity.net:msg:others-journals-only.html")
        let page = try await FANotificationsPage(data: data).unwrap()
        
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
        XCTAssertEqual([], page.submissionCommentHeaders)
        XCTAssertEqual([], page.journalCommentHeaders)
        XCTAssertEqual(expected, page.journalHeaders)
    }
    
    func testPageContainsSubmissionComments_listsComments() async throws {
        let data = testData("www.furaffinity.net:msg:others-submission-comments-only.html")
        let page = try await FANotificationsPage(data: data).unwrap()
        
        let expected: [FANotificationsPage.Header] = [
            .init(id: 172177443, author: "furrycount", displayAuthor: "Furrycount", title: "FurAffinity iOS App 1.3 Update",
                  datetime: "on Apr 30, 2023 09:50 PM", naturalDatetime: "a few seconds ago",
                  url: URL(string: "https://www.furaffinity.net/view/49215481/#cid:172177443")!),
            .init(id: 172177425, author: "furrycount", displayAuthor: "Furrycount", title: "FurAffinity iOS App 1.3 Update",
                  datetime: "on Apr 30, 2023 09:49 PM", naturalDatetime: "a minute ago",
                  url: URL(string: "https://www.furaffinity.net/view/49215481/#cid:172177425")!)
        ]
        XCTAssertEqual(expected, page.submissionCommentHeaders)
        XCTAssertEqual([], page.journalCommentHeaders)
        XCTAssertEqual([], page.journalHeaders)
    }
    
    func testPageContainsJournalComments_listsComments() async throws {
        let data = testData("www.furaffinity.net:msg:others-journal-comments-only.html")
        let page = try await FANotificationsPage(data: data).unwrap()

        let expected: [FANotificationsPage.Header] = [
            .init(id: 60479543, author: "ceylo", displayAuthor: "Ceylo", title: "Test",
                  datetime: "on Apr 22, 2024 02:11 PM", naturalDatetime: "couple of minutes ago",
                  url: URL(string: "https://www.furaffinity.net/journal/10528107/#cid:60479543")!)
        ]
        
        XCTAssertEqual([], page.submissionCommentHeaders)
        XCTAssertEqual(expected, page.journalCommentHeaders)
        XCTAssertEqual([], page.journalHeaders)
    }
}
