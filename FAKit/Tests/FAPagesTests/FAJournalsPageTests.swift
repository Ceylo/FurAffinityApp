//
//  File.swift
//  FAKit
//
//  Created by Ceylo on 11/10/2024.
//

import Foundation
import Testing
@testable import FAPages

struct FAJournalsPageTests {
    @Test func journalsPageWithNoJournal_isParsed() async throws {
        let data = testData("www.furaffinity.net:journals:maziurek-empty.html")
        let page = try await FAUserJournalsPage(data: data).unwrap()
        let expected = FAUserJournalsPage(
            displayAuthor: "Maziurek",
            journals: []
        )
        #expect(page == expected)
    }
    
    @Test func journalsPageWithJournals_isParsed() async throws {
        let data = testData("www.furaffinity.net:journals:tiaamaito:.html")
        let page = try await FAUserJournalsPage(data: data).unwrap()
        #expect(page.displayAuthor == "tiaamaito")
        #expect(page.journals.count == 25)
        #expect(page.journals.prefix(5) == [
            .init(id: 10954574, title: "I'll resume posting art!",
                  datetime: "Sep 14, 2024 04:17 AM", naturalDatetime: "5 months ago",
                  url: URL(string: "https://www.furaffinity.net/journal/10954574/")!),
            .init(id: 10893232, title: "fullbody commissions (CLOSED)",
                  datetime: "Jun 23, 2024 08:14 PM", naturalDatetime: "8 months ago",
                  url: URL(string: "https://www.furaffinity.net/journal/10893232/")!),
            .init(id: 10877414, title: "Pride themed group YCH closed!!",
                  datetime: "Jun 1, 2024 04:03 AM", naturalDatetime: "9 months ago",
                  url: URL(string: "https://www.furaffinity.net/journal/10877414/")!),
            .init(id: 10815815, title: "Change on commissions!",
                  datetime: "Mar 2, 2024 04:13 AM", naturalDatetime: "a year ago",
                  url: URL(string: "https://www.furaffinity.net/journal/10815815/")!),
            .init(id: 10691323, title: "Follow me on BlueSky! (and other places)",
                  datetime: "Sep 20, 2023 03:50 AM", naturalDatetime: "a year ago",
                  url: URL(string: "https://www.furaffinity.net/journal/10691323/")!),
        ])
    }
}

