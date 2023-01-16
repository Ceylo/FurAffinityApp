//
//  FASubmissionsPageTests.swift
//  
//
//  Created by Ceylo on 17/10/2021.
//

import XCTest
@testable import FAPages

final class FANotesPageTests: XCTestCase {
    func testEmptyInbox_returnsNoNote() async throws {
        let data = testData("www.furaffinity.net:msg:pms-empty.html")
        let page = await FANotesPage(data: data)
        XCTAssertNotNil(page)
        XCTAssertEqual([], page!.noteHeaders)
    }
    
    func testMessagesInInbox_returnsNotes() async throws {
        let data = testData("www.furaffinity.net:msg:pms-unread.html")
        let page = await FANotesPage(data: data)
        XCTAssertNotNil(page)
        
        let expected: [FANotesPage.NoteHeader] = [
            .init(id: 129953494, author: "someuser", displayAuthor: "SomeUser", title: "Another message",
                  datetime: "Apr 7, 2022 12:09PM", naturalDatetime: "8 months ago", unread: true,
                  noteUrl: URL(string: "https://www.furaffinity.net/msg/pms/1/129953494/#message")!),
            .init(id: 129953262, author: "someuser", displayAuthor: "SomeUser", title: "Title with some spéciäl çhãrāčtęrs",
                  datetime: "Apr 7, 2022 11:58AM", naturalDatetime: "8 months ago", unread: false,
                  noteUrl: URL(string: "https://www.furaffinity.net/msg/pms/1/129953262/#message")!)
        ]
        XCTAssertEqual(expected, page!.noteHeaders)
    }
}
