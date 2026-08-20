//
//  AttributedString+FAHTMLFragments.swift
//  FAKit
//
//  The carrier between `FAHTMLNormalizer` and the Android renderer.
//
//  `HTMLView` takes an `AttributedString` on both platforms — on iOS a real one, built by
//  WebKit's HTML importer. On Android nothing parses HTML into an attributed string, and
//  nothing needs to: Compose parses the markup itself. So each fragment's markup rides in
//  an attribute on runs whose characters are that same markup — the characters are what
//  keep the runs apart — and the view hands it straight to `Text(html:)`.
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
            attributed.faHTMLFragment = FAHTMLFragment(
                index: index, html: fragment.html, images: fragment.images
            )
            self += attributed
        }
    }

    /// The carried fragments, in document order. The markup rides in the attribute
    /// value, so this only has to walk the runs and skip the repeats.
    public var faHTMLFragments: [FAHTMLFragment] {
        var result: [FAHTMLFragment] = []
        for run in runs {
            guard let fragment = run.faHTMLFragment else { continue }
            if result.last?.index != fragment.index { result.append(fragment) }
        }
        return result
    }
}
