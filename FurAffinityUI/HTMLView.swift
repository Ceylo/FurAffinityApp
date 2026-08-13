//
//  HTMLView.swift
//  FurAffinityUI (Android)
//
//  Android counterpart of the iOS `HTMLView`. The iOS one is a `UIViewRepresentable`
//  over a manually sized `UITextView` with animated-GIF overlays; none of that exists
//  here. Instead FAKit's `FARichTextParser` hands over text tagged with `\.faInline` /
//  `\.faBlock`, and this view restates those as the SwiftUI attributes the skip-fuse-ui
//  bridge encodes for Compose.
//
//  `initialHeight` is accepted and ignored — it only ever seeded the iOS manual sizing.
//

import SwiftUI
import FAKit

struct HTMLView: View {
    var text: AttributedString

    init(text: AttributedString, initialHeight: CGFloat = 0) {
        self.text = text
    }

    var body: some View {
        Text(text.styledForDisplay)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Matches the iOS view's `textContainerInset = 3` on all edges.
            .padding(3)
    }
}

extension AttributedString {
    /// FA's parser attributes restated as the SwiftUI ones the Compose bridge reads.
    var styledForDisplay: AttributedString {
        var result = AttributedString()
        var previousBlock: Int?

        for run in runs {
            // Inline images and rules are carried on a U+FFFC placeholder, which draws
            // as a tofu box until each has a renderer of its own.
            guard run.faImage == nil, run.faBlock?.kind != .rule else { continue }

            if let block = run.faBlock?.index {
                if let previousBlock, previousBlock != block {
                    result += AttributedString("\n")
                }
                previousBlock = block
            }

            var styled = AttributedString(self[run.range])
            styled.applyFAInlineStyle(run.faInline ?? .default, isLink: run.link != nil)
            result += styled
        }
        return result
    }

    private mutating func applyFAInlineStyle(_ style: FAInlineStyle, isLink: Bool) {
        // Only state a font when the run actually differs, so everything else keeps
        // inheriting the environment's — and with it Dynamic Type.
        var font: Font?
        if style.sizeScale != 1 {
            font = .system(size: Self.faBodyPointSize * style.sizeScale)
        } else if style.bold || style.italic || style.monospace {
            font = .body
        }
        if var font {
            if style.bold { font = font.weight(.bold) }
            if style.italic { font = font.italic() }
            if style.monospace { font = font.monospaced() }
            self.font = font
        }

        if let argb = style.colorARGB {
            self.foregroundColor = Color(faARGB: argb)
        }
        // iOS underlines links with a dotted pattern, which Compose has no equivalent
        // for; a solid one is the closest available.
        if style.underline || isLink {
            self.underlineStyle = .single
        }
        if style.strikethrough {
            self.strikethroughStyle = .single
        }
        switch style.baseline {
        case .normal:
            break
        case .sub:
            self.baselineOffset = -3
        case .super:
            self.baselineOffset = 4
        }
    }

    /// FA's body text is 16px, which is what `FAInlineStyle.sizeScale` is relative to.
    private static let faBodyPointSize: Double = 16
}

private extension Color {
    init(faARGB argb: UInt32) {
        self.init(
            red: Double((argb >> 16) & 0xFF) / 255,
            green: Double((argb >> 8) & 0xFF) / 255,
            blue: Double(argb & 0xFF) / 255,
            opacity: Double((argb >> 24) & 0xFF) / 255
        )
    }
}
