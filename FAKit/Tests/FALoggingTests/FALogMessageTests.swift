//
//  FALogMessageTests.swift
//  FALoggingTests
//

import XCTest
@testable import FALogging

final class FALogMessageTests: XCTestCase {
    func testPlainStringLiteral() {
        let message: FALogMessage = "Next page requested but there is none!"
        XCTAssertEqual(message.rendered, "Next page requested but there is none!")
    }

    func testBareInterpolation() {
        let count = 5
        let message: FALogMessage = "Got \(count) submission previews"
        XCTAssertEqual(message.rendered, "Got 5 submission previews")
    }

    func testPublicPrivacyInterpolation() {
        let name = "device"
        let message: FALogMessage = "Launched on \(name, privacy: .public)"
        XCTAssertEqual(message.rendered, "Launched on device")
    }

    func testErrorInterpolation() {
        struct SampleError: Error, CustomStringConvertible {
            var description: String { "boom" }
        }
        let error: any Error = SampleError()
        let message: FALogMessage = "Failed: \(error, privacy: .public)"
        XCTAssertEqual(message.rendered, "Failed: boom")
    }

    func testMixedLiteralsAndInterpolations() {
        let url = URL(string: "https://furaffinity.net/x")!
        let n = 4
        let message: FALogMessage = "\(url) not recognized, expected 4 but got \(n)"
        XCTAssertEqual(
            message.rendered,
            "https://furaffinity.net/x not recognized, expected 4 but got 4"
        )
    }
}
