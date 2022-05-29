//
//  FAUserPageTests.swift
//  
//
//  Created by Ceylo on 05/12/2021.
//

import XCTest
@testable import FAPages

class FAUserPageTests: XCTestCase {
    func testUserPage_isParsed() throws {
        let data = testData("www.furaffinity.net:user:terriniss.html")
        let page = FAUserPage(data: data)
        XCTAssertNotNil(page)
        
        let expected = FAUserPage(
            userName: "terriniss",
            displayName: "Terriniss",
            avatarUrl: URL(string: "https://a.furaffinity.net/1616615925/terriniss.gif")!)
        XCTAssertEqual(page, expected)
    }
}
