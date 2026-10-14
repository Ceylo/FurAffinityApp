//
//  FAInterstitialTests.swift
//  FAKitTests
//

import Foundation
import Testing
@testable import FAKit

struct FAInterstitialDecodeTests {
    @Test
    func aJSONStringLiteralDecodesToItsText() {
        #expect(FAInterstitial.decodeEvaluatedString("\"\\u003Cdiv\\u003E\"") == "<div>")
    }

    @Test
    func anEscapedBackslashStaysLiteral() {
        // The injection case. Nine independent replacement passes with `\\` -> `\`
        // applied last turned this into a real `<div`, so page text holding the
        // characters `<div` became markup the FA parsers read as an element.
        #expect(FAInterstitial.decodeEvaluatedString("\"\\\\u003Cdiv\"") == "\\u003Cdiv")
    }

    @Test
    func anEscapedBackslashBeforeNIsNotANewline() {
        #expect(FAInterstitial.decodeEvaluatedString("\"a\\\\nb\"") == "a\\nb")
    }

    @Test
    func aQuoteInsideTheStringSurvives() {
        #expect(FAInterstitial.decodeEvaluatedString("\"quote \\\" here\"") == "quote \" here")
    }

    @Test
    func aRawStringIsLeftAlone() {
        // iOS's WebView hands back the value itself, not a JSON encoding of it.
        #expect(FAInterstitial.decodeEvaluatedString("<html>raw</html>") == "<html>raw</html>")
    }

    @Test
    func anUnquotedButEscapedValueStillDecodes() {
        // skip-web has been seen returning this shape too.
        #expect(FAInterstitial.decodeEvaluatedString("\\u003Cdiv\\u003E") == "<div>")
    }
}
