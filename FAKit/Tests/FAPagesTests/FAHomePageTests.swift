//
//  FAHomePageTests.swift
//
//
//  Created by Ceylo on 17/10/2021.
//

import Testing
@testable import FAPages

struct FAHomePageTests {
    @Test
    func loggedOutPage_parsedAsExpected() {
        let data = testData("www.furaffinity.net:loggedout.html")
        #expect(throws: (any Error).self) {
            try FAHomePage(data: data, url: FAURLs.homeUrl)
        }
    }

    @Test
    func loggedInPage_parsedAsExpected() throws {
        let data = testData("www.furaffinity.net:loggedin.html")
        let page = try FAHomePage(data: data, url: FAURLs.homeUrl)

        #expect(page == .init(
            username: "furrycount",
            displayUsername: "Furrycount"
        ))
    }
}
