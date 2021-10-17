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
        let loggedOutHtml = htmlPath("www.furaffinity.net-loggedout")
        let data = try Data(contentsOf: loggedOutHtml)
        let page = FAHomePage(data: data)
        XCTAssertNotNil(page)
        XCTAssertNil(page?.username)
        XCTAssertNil(page?.displayUsername)
        XCTAssertNil(page?.submissionsCount)
        XCTAssertNil(page?.journalsCount)
    }
    
    func testLoggedInPage_parsedAsExpected() throws {
        let loggedInHtml = htmlPath("www.furaffinity.net-loggedin")
        let data = try Data(contentsOf: loggedInHtml)
        let page = FAHomePage(data: data)
        XCTAssertNotNil(page)
        XCTAssertEqual(page?.username, "furrycount")
        XCTAssertEqual(page?.displayUsername, "Furrycount")
        XCTAssertEqual(page?.submissionsCount, 1514)
        XCTAssertEqual(page?.journalsCount, 193)
    }
}
