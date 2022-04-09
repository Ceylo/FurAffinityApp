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
        let page = FANotesPage(data: data)
        XCTAssertNotNil(page)
        XCTAssertEqual([], page!.noteHeaders)
    }
    
    func testMessagesInInbox_returnsNotes() throws {
        let data = testData("www.furaffinity.net:msg:pms-unread.html")
        let page = FANotesPage(data: data)
        XCTAssertNotNil(page)
        
        let expected: [FANotesPage.NoteHeader] = [
            .init(id: 129953494, author: "someuser", displayAuthor: "SomeUser", title: "Another message",
                  datetime: "Apr 7, 2022 12:09PM", unread: true,
                  noteUrl: URL(string: "https://www.furaffinity.net/msg/pms/1/129953494/#message")!),
            .init(id: 129953262, author: "someuser", displayAuthor: "SomeUser", title: "Title with some spéciäl çhãrāčtęrs",
                  datetime: "Apr 7, 2022 11:58AM", unread: false,
                  noteUrl: URL(string: "https://www.furaffinity.net/msg/pms/1/129953262/#message")!)
        ]
        XCTAssertEqual(expected, page!.noteHeaders)
    }
}
