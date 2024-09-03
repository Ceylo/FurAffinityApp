//
//  String.swift
//  FurAffinityTests
//
//  Created by Ceylo on 03/09/2024.
//

import Testing
@testable import Fur_Affinity

struct StringTests {
    @Test("containsAllOrderedCharacters", arguments: [
        ("", "", true),
        ("", "a", false),
        ("abc", "", true),
        ("abc", "b", true),
        ("abc", "abc", true),
        ("abc", "ac", true),
        ("abc", "AC", true),
        ("ABC", "ac", true),
        ("abc", "acd", false),
        ("abc", "abcd", false),
    ]) func containsAllOrderedCharacters(args: (parent: String, pattern: String, result: Bool)) async throws {
        #expect(args.parent.containsAllOrderedCharacters(from: args.pattern) == args.result)
    }

}
