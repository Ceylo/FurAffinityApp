//
//  FAUsername.swift
//  FAKit
//
//  Created by Ceylo on 04/07/2026.
//

import Foundation

/// Validation for a static (lowercase) FurAffinity username — the `author` /
/// `username` form used in URLs and the `@lower` search operator, not the
/// free-form `displayAuthor`.
public enum FAUsername {
    /// Characters allowed in a static FA username: lowercase letters, digits,
    /// and `^~`.-`.
    public static let allowedCharset = CharacterSet
        .lowercaseLetters
        .union(.decimalDigits)
        .union(.init(charactersIn: "^~`.-"))

    /// Whether `username` is a non-empty, well-formed static FA username.
    public static func isValid(_ username: String) -> Bool {
        guard !username.isEmpty else { return false }
        return allowedCharset.isSuperset(of: CharacterSet(charactersIn: username))
    }
}
