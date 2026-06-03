//
//  FALogMessageTests.swift
//  FALoggingTests
//

import Testing
import Foundation
@testable import FALogging

struct FALogMessageTests {
    @Test
    func plainStringLiteral() {
        let message: FALogMessage = "Next page requested but there is none!"
        #expect(message.rendered == "Next page requested but there is none!")
    }

    @Test
    func bareInterpolation() {
        let count = 5
        let message: FALogMessage = "Got \(count) submission previews"
        #expect(message.rendered == "Got 5 submission previews")
    }

    @Test
    func publicPrivacyShowsValue() {
        let name = "device"
        let message: FALogMessage = "Launched on \(name, privacy: .public)"
        #expect(message.rendered == "Launched on device")
    }

    @Test
    func autoPrivacyShowsValue() {
        let n = 7
        let message: FALogMessage = "n=\(n, privacy: .auto)"
        #expect(message.rendered == "n=7")
    }

    // Privacy must NOT redact here: this matches os.Logger read from the same
    // process (OSLogStore .currentProcessIdentifier) / with a debugger attached,
    // where .private and .sensitive values appear in full.
    @Test
    func privatePrivacyStillShowsValue() {
        let token = "secret-abc"
        let message: FALogMessage = "token=\(token, privacy: .private)"
        #expect(message.rendered == "token=secret-abc")
    }

    @Test
    func sensitivePrivacyStillShowsValue() {
        let password = "hunter2"
        let message: FALogMessage = "pwd=\(password, privacy: .sensitive)"
        #expect(message.rendered == "pwd=hunter2")
    }

    @Test
    func errorInterpolation() {
        struct SampleError: Error, CustomStringConvertible {
            var description: String { "boom" }
        }
        let error: any Error = SampleError()
        let message: FALogMessage = "Failed: \(error, privacy: .public)"
        #expect(message.rendered == "Failed: boom")
    }

    @Test
    func mixedLiteralsAndInterpolations() {
        let url = URL(string: "https://furaffinity.net/x")!
        let n = 4
        let message: FALogMessage = "\(url) not recognized, expected 4 but got \(n)"
        #expect(message.rendered == "https://furaffinity.net/x not recognized, expected 4 but got 4")
    }
}
