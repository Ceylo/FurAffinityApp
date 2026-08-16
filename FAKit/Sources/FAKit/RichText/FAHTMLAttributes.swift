//
//  FAHTMLAttributes.swift
//  FAKit
//
//  What `FAHTMLNormalizer` hands the Android renderer, and the attribute that carries it.
//
//  Corelibs Foundation has no `InlinePresentationIntent` or `PresentationIntent`, but it
//  does support custom `AttributedStringKey`s — which is all that is needed now that
//  Compose parses the markup itself: the string carries the markup verbatim and this
//  names which fragment each run belongs to.
//
//  Cross-platform on purpose: only Android renders through it, but it is built and
//  unit-tested on iOS.
//

import Foundation

/// An `<img>` the HTML parser drops, leaving a U+FFFC where it was.
public struct FAInlineImage: Hashable, Sendable, Codable {
    public var url: URL
    /// Intrinsic size from the HTML attributes, when the markup states one.
    public var width: Double?
    public var height: Double?
    public var alt: String?
    /// FA's `.iconusername` avatars, which the site's CSS caps at 50×50.
    public var isAvatar: Bool

    public init(url: URL, width: Double? = nil, height: Double? = nil,
                alt: String? = nil, isAvatar: Bool = false) {
        self.url = url
        self.width = width
        self.height = height
        self.alt = alt
        self.isAvatar = isAvatar
    }
}

/// A fragment of normalised markup carried inside an `AttributedString`.
///
/// `HTMLView` takes an `AttributedString` on both platforms — iOS renders one for real —
/// so on Android the string carries the markup as its characters and this on the runs,
/// naming which fragment they belong to and which images its placeholders stand for.
public struct FAHTMLFragment: Hashable, Sendable, Codable {
    /// Monotonic per-document. Consecutive fragments were separated by an `<hr>`.
    public var index: Int
    public var images: [FAInlineImage]

    public init(index: Int, images: [FAInlineImage]) {
        self.index = index
        self.images = images
    }
}

public enum FAAttributes {
    public enum HTMLFragmentAttribute: AttributedStringKey {
        public typealias Value = FAHTMLFragment
        public static let name = "FAHTMLFragment"
    }
}

extension AttributeScopes {
    public struct FAAttributeScope: AttributeScope {
        public let faHTMLFragment: FAAttributes.HTMLFragmentAttribute
    }

    public var fa: FAAttributeScope.Type { FAAttributeScope.self }
}

extension AttributeDynamicLookup {
    public subscript<T: AttributedStringKey>(
        dynamicMember keyPath: KeyPath<AttributeScopes.FAAttributeScope, T>
    ) -> T {
        self[T.self]
    }
}
