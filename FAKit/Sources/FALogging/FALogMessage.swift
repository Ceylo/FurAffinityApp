//
//  FALogMessage.swift
//  FALogging
//
//  Log message type that mirrors os.Logger's string-interpolation syntax
//  (`"... \(value) ... \(value, privacy: .public) ..."`) so existing call
//  sites compile unchanged, while letting us capture the composed string for
//  persistent file logging.
//

import Foundation

/// Privacy qualifier for interpolated values, mirroring `os.Logger`'s.
///
/// `.public` and `.auto` render the value; `.private` and `.sensitive` redact it
/// to `<private>`. The default is `.public` so that unannotated interpolations
/// (and the codebase's existing `privacy: .public` ones) keep producing full
/// values in the diagnostic log — matching the old `OSLogStore` export, which
/// could read this process's own private values. Mark genuinely sensitive
/// values `.private`/`.sensitive` to keep them out of the exported file.
public enum FALogPrivacy: Sendable {
    case `public`
    case `private`
    case sensitive
    case auto

    var redacts: Bool {
        switch self {
        case .public, .auto: return false
        case .private, .sensitive: return true
        }
    }
}

/// A log message built from a string literal or interpolation. The interpolated
/// value is rendered eagerly into `rendered`.
public struct FALogMessage: ExpressibleByStringLiteral, ExpressibleByStringInterpolation, Sendable {
    /// The fully composed message text.
    public let rendered: String

    public init(stringLiteral value: String) {
        self.rendered = value
    }

    public init(stringInterpolation: StringInterpolation) {
        self.rendered = stringInterpolation.text
    }

    public struct StringInterpolation: StringInterpolationProtocol {
        var text: String

        public init(literalCapacity: Int, interpolationCount: Int) {
            text = ""
            text.reserveCapacity(literalCapacity + interpolationCount * 8)
        }

        public mutating func appendLiteral(_ literal: String) {
            text.append(literal)
        }

        /// A single unconstrained generic overload covers every interpolation
        /// form used in the codebase (`\(x)` and `\(x, privacy: .public)`) for
        /// any value type, with no overload ambiguity. Redacting values is done
        /// here (not at render time) so the value closure isn't even evaluated
        /// when redacted.
        public mutating func appendInterpolation<T>(
            _ value: @autoclosure () -> T,
            privacy: FALogPrivacy = .public
        ) {
            text.append(privacy.redacts ? "<private>" : String(describing: value()))
        }
    }
}
