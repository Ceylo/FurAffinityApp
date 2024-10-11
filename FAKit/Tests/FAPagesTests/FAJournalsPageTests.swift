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
        let page = try await FAJournalsPage(data: data).unwrap()
        #expect(page.journals.isEmpty)
    }
    
    @Test func journalsPageWithJournals_isParsed() async throws {
        let data = testData("www.furaffinity.net:journals:tiaamaito.html")
        let page = try await FAJournalsPage(data: data).unwrap()
        #expect(page.journals.count == 25)
        #expect(page.journals.prefix(5) == [
            .init(id: 10954574, title: "I'll resume posting art!",
                  datetime: "Sep 14, 2024 03:17 AM", naturalDatetime: "a month ago",
                  url: URL(string: "https://www.furaffinity.net/journal/10954574/")!),
            .init(id: 10893232, title: "fullbody commissions (CLOSED)",
                  datetime: "Jun 23, 2024 07:14 PM", naturalDatetime: "3 months ago",
                  url: URL(string: "https://www.furaffinity.net/journal/10893232/")!),
            .init(id: 10877414, title: "Pride themed group YCH closed!!",
                  datetime: "Jun 1, 2024 03:03 AM", naturalDatetime: "4 months ago",
                  url: URL(string: "https://www.furaffinity.net/journal/10877414/")!),
            .init(id: 10815815, title: "Change on commissions!",
                  datetime: "Mar 2, 2024 03:13 AM", naturalDatetime: "7 months ago",
                  url: URL(string: "https://www.furaffinity.net/journal/10815815/")!),
            .init(id: 10691323, title: "Follow me on BlueSky! (and other places)",
                  datetime: "Sep 20, 2023 02:50 AM", naturalDatetime: "a year ago",
                  url: URL(string: "https://www.furaffinity.net/journal/10691323/")!),
        ])
    }
}

