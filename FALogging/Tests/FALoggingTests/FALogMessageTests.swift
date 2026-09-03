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
    func errorInterpolation() {
        struct SampleError: Error, CustomStringConvertible {
            var description: String { "boom" }
        }
        let error: any Error = SampleError()
        let message: FALogMessage = "Failed: \(error)"
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
