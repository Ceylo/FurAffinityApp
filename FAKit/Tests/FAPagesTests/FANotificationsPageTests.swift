//
//  FASubmissionsPageTests.swift
//  
//
//  Created by Ceylo on 17/10/2021.
//

import XCTest
@testable import FAPages

final class FANotificationsPageTests: XCTestCase {
    func testWithAllNotifications_returnsAllNotifications() async throws {
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
    
    func testEmpty_returnsNoNotification() async throws {
        let data = testData("www.furaffinity.net:msg:others-empty.html")
        let page = try await FANotificationsPage(data: data).unwrap()
        let expected = FANotificationsPage(
            submissionCommentHeaders: [],
            journalCommentHeaders: [],
            shoutHeaders: [],
            journalHeaders: []
        )
        XCTAssertEqual(expected, page)
    }
}
