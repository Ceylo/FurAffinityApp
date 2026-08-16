//
//  FARichTextAttributes.swift
//  FAKit
//
//  The attribute vocabulary `FARichTextParser` emits.
//
//  Apple's `AttributedString(FAHTML:)` rides on WebKit's HTML importer, whose output
//  already carries `\.font`, `\.foregroundColor`, `NSAttachment` & friends. Corelibs
//  Foundation has none of that machinery (no `InlinePresentationIntent`, no
//  `PresentationIntent`), but it does support custom `AttributedStringKey`s — so the
//  Android pipeline carries FA's styling in these three keys instead and lets the
//  renderer decide how each maps onto Compose.
//
//  Cross-platform on purpose: the parser compiles and is unit-tested on iOS even though
//  only Android calls it.
//

import Foundation

/// Character-level styling of a run: everything FA's markup can say about a span of text.
public struct FAInlineStyle: Hashable, Sendable, Codable {
    public enum Baseline: String, Hashable, Sendable, Codable {
        case normal, sub, `super`
    }

    public var bold = false
    public var italic = false
    public var underline = false
    public var strikethrough = false
    public var monospace = false
    /// Literal colour from the markup (`0xAARRGGBB`), or nil to inherit the theme's.
    public var colorARGB: UInt32?
    /// Font size relative to FA's 16px body text.
    public var sizeScale: Double = 1
    public var baseline: Baseline = .normal

    public static let `default` = FAInlineStyle()

    public init() {}
}

/// The block a run belongs to. Runs sharing an `index` form one paragraph-like unit.
public struct FABlock: Hashable, Sendable, Codable {
    public enum Kind: Hashable, Sendable, Codable {
        case paragraph
        case heading(level: Int)
        case quote
        case listItem(depth: Int, ordinal: Int?)
        case rule
    }

    public enum Alignment: String, Hashable, Sendable, Codable {
        case leading, center, trailing
    }

    public var kind: Kind
    public var alignment: Alignment
    /// Monotonic per-document index. Without it two adjacent blocks that are otherwise
    /// identical would merge into a single `AttributedString` run and lose their break.
    public var index: Int

    public init(kind: Kind, alignment: Alignment, index: Int) {
        self.kind = kind
        self.alignment = alignment
        self.index = index
    }
}

/// An `<img>`, carried on a single `\u{FFFC}` (object replacement) character.
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

    public enum InlineStyleAttribute: AttributedStringKey {
        public typealias Value = FAInlineStyle
        public static let name = "FAInlineStyle"
    }

    public enum BlockAttribute: AttributedStringKey {
        public typealias Value = FABlock
        public static let name = "FABlock"
    }

    public enum ImageAttribute: AttributedStringKey {
        public typealias Value = FAInlineImage
        public static let name = "FAInlineImage"
    }
}

extension AttributeScopes {
    public struct FAAttributeScope: AttributeScope {
        public let faHTMLFragment: FAAttributes.HTMLFragmentAttribute
        public let faInline: FAAttributes.InlineStyleAttribute
        public let faBlock: FAAttributes.BlockAttribute
        public let faImage: FAAttributes.ImageAttribute
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

/// One paragraph-like unit of a parsed document: what a block renderer draws as a row.
public struct FARichTextBlock: Hashable, Sendable {
    public var block: FABlock
    public var text: AttributedString

    public init(block: FABlock, text: AttributedString) {
        self.block = block
        self.text = text
    }
}

extension AttributedString {
    /// The document's blocks in order, each as its own slice.
    ///
    /// Runs carry `\.faBlock`; this regroups them into the units a block renderer draws.
    public var faBlocks: [FARichTextBlock] {
        var result: [FARichTextBlock] = []
        for run in runs {
            guard let block = run.faBlock else { continue }
            if result.last?.block.index == block.index {
                result[result.count - 1].text += self[run.range]
            } else {
                result.append(FARichTextBlock(block: block,
                                              text: AttributedString(self[run.range])))
            }
        }
        return result
    }
}
