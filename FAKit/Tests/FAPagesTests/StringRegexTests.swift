//
//  StringRegexTests.swift
//

import Testing
@testable import FAPages

struct StringRegexTests {
    @Test func matchReturnsFirstCaptureGroup() {
        #expect("hello world".substring(matching: "(\\w+) world") == "hello")
    }

    @Test func noMatchReturnsNil() {
        #expect("hello".substring(matching: "(\\d+)") == nil)
    }

    @Test func emptyStringReturnsNil() {
        #expect("".substring(matching: "(\\w+)") == nil)
    }

    @Test func invalidRegexReturnsNil() {
        #expect("hello".substring(matching: "[invalid(") == nil)
    }
}
