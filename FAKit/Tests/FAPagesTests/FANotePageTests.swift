//
//  FANotePageTests.swift
//  
//
//  Created by Ceylo on 17/10/2021.
//

import Testing
@testable import FAPages

struct FANotePageTests {
    @Test func parseNote_returnsNoteDetails() throws {
        let data = testData("www.furaffinity.net:msg:pms-contents.html")
        let page = FANotePage(data: data)
        #expect(page != nil)
        
        let expected = FANotePage(
            author: "ceylo", displayAuthor: "Ceylo",
            title: "RE: Fur Affinity app update",
            datetime: "May 10th, 2024, 04:41 AM",
            naturalDatetime: "a year ago",
            htmlMessage: """
<i class="fa-app-warning" style="color: red;">
 <div class="noteWarningMessage noteWarningMessage--scam user-submitted-links"> 
  <div class="noteWarningMessage__icon"> 
   <img src="/themes/beta/img/icons/Error_l.png" /> 
  </div> 
  <div> 
   <h4>Do you know this person?</h4> Verify the username and profile before doing business with them! Scammers often attempt to impersonate well-known artists. 
   <br /> If you encounter something suspicious, please report it using a 
   <a href="/controls/troubletickets/">Trouble Ticket</a>. 
  </div> 
  <br />
 </div></i> Hey there,
<br /> I hope you enjoyed the changes in the latest app version!
<br /> If you'd like to see specific changes or have some troubles with it, please let me know! 💕
<br /> 
<br /> Have a nice day 🎉
""",
            htmlMessageWithoutWarning: """
Hey there,
<br /> I hope you enjoyed the changes in the latest app version!
<br /> If you'd like to see specific changes or have some troubles with it, please let me know! 💕
<br /> 
<br /> Have a nice day 🎉
""",
            answerKey: "610f9fce70ea99201551feef626a2a274c6497ee4a7a83828058b095046ac486",
            answerPlaceholderMessage: """


—————————
original post by Ceylo (@ceylo):

Hey there,
I hope you enjoyed the changes in the latest app version!
If you'd like to see specific changes or have some troubles with it, please let me know! 💕

Have a nice day 🎉
"""
        )
        #expect(expected == page)
        #expect(expected.author == page?.author)
        #expect(expected.displayAuthor == page?.displayAuthor)
        #expect(expected.title == page?.title)
        #expect(expected.datetime == page?.datetime)
        #expect(expected.naturalDatetime == page?.naturalDatetime)
        #expect(expected.htmlMessage == page?.htmlMessage)
        #expect(expected.htmlMessageWithoutWarning == page?.htmlMessageWithoutWarning)
        #expect(expected.answerKey == page?.answerKey)
        #expect(expected.answerPlaceholderMessage == page?.answerPlaceholderMessage)
    }
}
