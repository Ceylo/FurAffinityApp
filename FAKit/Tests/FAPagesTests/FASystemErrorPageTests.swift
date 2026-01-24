//
//  FASystemErrorPageTests.swift
//
//
//  Created by Ceylo on 17/10/2021.
//

import Testing
@testable import FAPages

struct FASystemErrorPageTests {
    @Test func parseUnknownUserPage_providesMessage() throws {
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
    
    @Test func parseDisabledUserPage_providesMessage() throws {
        let data = testData("www.furaffinity.net:user:disabled-user-message.html")
        let page = try FASystemMessagePage(data: data)
        let expected = FASystemMessagePage(
            message: """
                Access has been disabled to the account and contents of user Misa.
                
                If this is your userpage and you would like to re-enable it, you may do so by contacting accounts[dot]furaffinity.net and requesting your account be re-enabled. 
                
                If you came here to unwatch this user you may do so by clicking the following link: unwatch Misa
                """
        )
        #expect(page == expected)
    }
    
    @Test func parseUserPendingDeletionPage_providesMessage() throws {
        let data = testData("www.furaffinity.net:user:pending-deletion-message.html")
        let page = try FASystemMessagePage(data: data)
        let expected = FASystemMessagePage(
            message: "The page you are trying to reach is currently pending deletion by a request from the administration."
        )
        #expect(page == expected)
    }
}
