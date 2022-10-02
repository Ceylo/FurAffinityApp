//
//  CodableHTTPCookie.swift
//  
//  Based on CodableHTTPCookie from https://github.com/sbertix/ComposableRequest/
//

import Foundation

/// A `subclass` of `HTTPCookie` conforming to `Codable`.
public final class CodableHTTPCookie: HTTPCookie, Codable {
    /// Init.
    /// - parameter properties: A valid `Dictionary` of `Any`.
    override public init?(properties: [HTTPCookiePropertyKey: Any]) {
        super.init(properties: properties)
    }

    /// Init.
    /// - parameter cookie: A valid `HTTPCookie`.
    public convenience init?(_ cookie: HTTPCookie) {
        guard let properties = cookie.properties else { return nil }
        self.init(properties: properties)
    }

    /// Init.
    /// - parameter decoder: A valid `Decoder`.
    public convenience init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // swiftlint:disable force_unwrapping
        self.init(properties: try container.decode([HTTPCookiePropertyKey: String].self))!
        // swiftlint:enable force_unwrapping
    }

    /// Encode.
    /// - parameter encoder: A valid `Encoder`.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(properties?.compactMapValues { $0 as? String } ?? [:])
    }
}

/// `HTTPCookiePropertyKey` conformacy to `Codable`.
extension HTTPCookiePropertyKey: Codable {
    /// Init.
    /// - parameter decoder: A valid `Decoder`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = try HTTPCookiePropertyKey(container.decode(String.self))
    }

    /// Encode.
    /// - parameter encoder: A valid `Encoder`.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
