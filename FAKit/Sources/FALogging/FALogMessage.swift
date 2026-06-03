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

/// Privacy qualifier accepted at call sites for syntax compatibility with
/// `os.Logger`.
///
/// It intentionally does **not** redact the persisted value. In `os.Logger`,
/// `.private`/`.sensitive` data is still written to the log store in full and is
/// only masked as `<private>` for *unprivileged* readers (Console.app on a user
/// device, sysdiagnose). The same process reading its own logs via
/// `OSLogStore(scope: .currentProcessIdentifier)` — which is exactly what the
/// old log export did — and any debugger-attached session see the real values.
/// This persistent file is that same self-read/privileged context, so to match
/// `os.Logger` we render every value in full regardless of privacy.
public enum FALogPrivacy: Sendable {
    case `public`
    case `private`
    case sensitive
    case auto
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
        /// any value type, with no overload ambiguity. `privacy` is accepted for
        /// `os.Logger` syntax compatibility; see `FALogPrivacy` for why it does
        /// not redact in this self-read context.
        public mutating func appendInterpolation<T>(
            _ value: @autoclosure () -> T,
            privacy: FALogPrivacy = .public
        ) {
            text.append(String(describing: value()))
        }
    }
}
