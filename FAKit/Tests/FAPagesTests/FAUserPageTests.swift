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
        let data = testData("www.furaffinity.net:user:annetpeas.html")
        let page = FAUserPage(data: data)
        XCTAssertNotNil(page)
        
        let expected = FAUserPage(
            userName: "annetpeas",
            displayName: "AnnetPeas",
            avatarUrl: URL(string: "https://a.furaffinity.net/1638303195/annetpeas.gif")!)
        XCTAssertEqual(page, expected)
    }

}
