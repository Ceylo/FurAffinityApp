//
//  FANotePageTests.swift
//  
//
//  Created by Ceylo on 17/10/2021.
//

import Testing
@testable import FAPages

struct FANewNotePageTests {
    @Test func parseNewNotePage_providesAPIKey() throws {
        let data = testData("www.furaffinity.net:newpm:username.html")
        let page = FANewNotePage(data: data)
        let expected = FANewNotePage(
            apiKey: "ef4475a2311353fd9f667ba9d6956af8ab721e63a2d73d855ebc51acef09e54d"
        )
        #expect(page == expected)
    }
}
