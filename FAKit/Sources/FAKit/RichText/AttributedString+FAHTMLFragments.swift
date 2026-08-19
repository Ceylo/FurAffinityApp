//
//  AttributedString+FAHTMLFragments.swift
//  FAKit
//
//  The carrier between `FAHTMLNormalizer` and the Android renderer.
//
//  `HTMLView` takes an `AttributedString` on both platforms — on iOS a real one, built by
//  WebKit's HTML importer. On Android nothing parses HTML into an attributed string, and
//  nothing needs to: Compose parses the markup itself. So the string carries the markup
//  verbatim as its characters, tagged run by run with the fragment it belongs to, and the
//  view hands each fragment's markup straight to `Text(html:)`.
//
//  Cross-platform on purpose: only Android builds one, but it is unit-tested on iOS.
//

import Foundation

extension AttributedString {
    /// A carrier holding each fragment's markup, tagged so the renderer can tell them
    /// apart — consecutive fragments were separated by a rule.
    public init(faHTMLFragments fragments: [FANormalizedHTML.Fragment]) {
        self.init()
        for (index, fragment) in fragments.enumerated() {
            var attributed = AttributedString(fragment.html)
            attributed.faHTMLFragment = FAHTMLFragment(index: index, images: fragment.images)
            self += attributed
        }
    }

    /// The carried fragments, in document order.
    public var faHTMLFragments: [FAHTMLFragment.Carried] {
        var result: [FAHTMLFragment.Carried] = []
        for run in runs {
            guard let fragment = run.faHTMLFragment else { continue }
            if result.last?.fragment.index == fragment.index {
                result[result.count - 1].html += String(self[run.range].characters)
            } else {
                result.append(FAHTMLFragment.Carried(
                    fragment: fragment,
                    html: String(self[run.range].characters)
                ))
            }
        }
        return result
    }
}

extension FAHTMLFragment {
    /// One fragment with the markup its runs carried.
    public struct Carried: Hashable, Sendable {
        public var fragment: FAHTMLFragment
        public var html: String

        public init(fragment: FAHTMLFragment, html: String) {
            self.fragment = fragment
            self.html = html
        }
    }
}
