//
//  FASubmissionsPageTests.swift
//  
//
//  Created by Ceylo on 17/10/2021.
//

import XCTest
@testable import FAPages

final class FANotesPageTests: XCTestCase {
    func testEmptyInbox_returnsNoNote() throws {
        let data = testData("www.furaffinity.net:msg:pms-empty.html")
        let page = try FANotesPage(data: data, url: URL(string: "https://www.furaffinity.net/msg/pms/")!)
        XCTAssertEqual([], page.noteHeaders)
    }
    
    func testMessagesInInbox_returnsNotes() throws {
        let data = testData("www.furaffinity.net:msg:pms-unread.html")
        let page = try FANotesPage(data: data, url: URL(string: "https://www.furaffinity.net/msg/pms/")!)
        
        let expected: [FANotesPage.NoteHeader] = [
            .init(
                id: 141712666,
                author: "someuser",
                displayAuthor: "SomeUser",
                title: "Fur Affinity app update",
                datetime: "May 10, 2024 04:41AM",
                naturalDatetime: "9 months ago",
                unread: true,
                noteUrl: URL(string: "https://www.furaffinity.net/msg/pms/1/141712666/#message")!
            )
        ]
        XCTAssertEqual(expected, page.noteHeaders)
    }
}
