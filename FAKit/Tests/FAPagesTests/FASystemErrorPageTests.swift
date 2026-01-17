//
//  FANotePageTests.swift
//  
//
//  Created by Ceylo on 17/10/2021.
//

import Testing
@testable import FAPages

struct FASystemErrorPageTests {
    @Test func parseSystemErrorPage_providesErrorMessage() throws {
        let data = testData("www.furaffinity.net:user:username-system-error.html")
        let page = try FASystemErrorPage(data: data)
        let expected = FASystemErrorPage(
            message: """
                This user cannot be found.

                Here are a few suggestions to help you out:
                • Check that the username is spelled correctly.
                • Try to do what you were doing again, but take out any odd symbols, spaces, and underscores.
                """
        )
        #expect(page == expected)
    }
}
