//
//  FATargetTests.swift
//  FurAffinityTests
//
//  Created by Ceylo on 17/03/2023.
//

import Testing
import Foundation
@testable import Fur_Affinity

struct FATargetTests {
    @Test
    func notMatching() {
        let url = URL(string: "https://www.patreon.com/")!
        #expect(FATarget(with: url) == nil)
    }

    @Test
    func matchingUser() {
        let userUrl = URL(string: "https://www.furaffinity.net/user/xyz")!
        #expect(FATarget(with: userUrl) == .user(url: userUrl, previewData: nil))
    }

    @Test
    func matchingSubmission() {
        let submissionUrl = URL(string: "https://www.furaffinity.net/view/123/")!
        #expect(FATarget(with: submissionUrl) == .submission(url: submissionUrl, previewData: nil))
    }

    @Test
    func matchingNote() {
        let noteUrl = URL(string: "https://www.furaffinity.net/msg/pms/1/234/#message")!
        #expect(FATarget(with: noteUrl) == .note(url: noteUrl))
    }

    @Test
    func matchingJournal() {
        let journalUrl = URL(string: "https://www.furaffinity.net/journal/10516170/")!
        #expect(FATarget(with: journalUrl) == .journal(url: journalUrl))
    }
}
