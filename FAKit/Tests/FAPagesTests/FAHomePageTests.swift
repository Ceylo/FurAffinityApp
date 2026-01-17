//
//  FAHomePageTests.swift
//
//
//  Created by Ceylo on 17/10/2021.
//

import XCTest
@testable import FAPages

final class FAHomePageTests: XCTestCase {
    func testLoggedOutPage_parsedAsExpected() {
        let data = testData("www.furaffinity.net:loggedout.html")
        XCTAssertThrowsError(try FAHomePage(data: data, url: FAURLs.homeUrl))
    }
    
    func testLoggedInPage_parsedAsExpected() throws {
        let data = testData("www.furaffinity.net:loggedin.html")
        let page = try FAHomePage(data: data, url: FAURLs.homeUrl)
        
        XCTAssertEqual(page, .init(
            username: "furrycount",
            displayUsername: "Furrycount"
        ))
    }
}
