//
//  FAHomePageTests.swift
//
//
//  Created by Ceylo on 17/10/2021.
//

import XCTest
@testable import FAPages

final class FAHomePageTests: XCTestCase {
    func testLoggedOutPage_parsedAsExpected() throws {
        let data = testData("www.furaffinity.net:loggedout.html")
        let page = FAHomePage(data: data, baseUri: FAURLs.homeUrl)
        XCTAssertNil(page)
    }
    
    func testLoggedInPage_parsedAsExpected() throws {
        let data = testData("www.furaffinity.net:loggedin.html")
        let page = try XCTUnwrap(FAHomePage(data: data, baseUri: FAURLs.homeUrl))
        
        XCTAssertEqual(page, .init(
            username: "furrycount",
            displayUsername: "Furrycount"
        ))
    }
}
