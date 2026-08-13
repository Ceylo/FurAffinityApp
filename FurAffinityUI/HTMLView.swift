//
//  HTMLView.swift
//  FurAffinityUI (Android)
//
//  Android counterpart of the iOS `HTMLView`. The iOS one is a `UIViewRepresentable`
//  over a manually sized `UITextView` with animated-GIF overlays; none of that exists
//  here. Instead FAKit's `FARichTextParser` hands over text tagged with `\.faInline` /
//  `\.faBlock`, and this view lays the blocks out itself, restating each run's styling
//  as the SwiftUI attributes the skip-fuse-ui bridge encodes for Compose.
//
//  A block is what a browser would lay out on its own line — a paragraph, a heading, a
//  quote, a rule, a list item. Alignment is the reason they can't collapse into one
//  `Text`: Compose applies `textAlign` per text node, so a centred `[center]` block and
//  the left-aligned text around it have to be separate views.
//
//  `initialHeight` is accepted and ignored — it only ever seeded the iOS manual sizing.
//

import SwiftUI
import FAKit

struct HTMLView: View {
    var text: AttributedString
    @Environment(\.colorScheme) var colorScheme

    init(text: AttributedString, initialHeight: CGFloat = 0) {
        self.text = text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(text.faBlocks, id: \.block.index) { entry in
                block(entry.block, text: entry.text.styledForDisplay)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Matches the iOS view's `textContainerInset = 3` on all edges.
        .padding(3)
    }

    @ViewBuilder
    private func block(_ block: FABlock, text: AttributedString) -> some View {
        switch block.kind {
        case .rule:
            Divider()
        case .quote:
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(Color.secondary)
                    .frame(width: 3)
                paragraph(text, alignment: block.alignment)
            }
        case .listItem(let depth, let ordinal):
            HStack(alignment: .top, spacing: 6) {
                Text(ordinal.map { "\($0)." } ?? "•")
                paragraph(text, alignment: block.alignment)
            }
            .padding(.leading, Double(depth - 1) * 16)
        case .heading(let level):
            paragraph(text, alignment: block.alignment)
                .font(.system(size: Self.headingPointSize(level)))
                .foregroundStyle(headingColor)
        case .paragraph:
            paragraph(text, alignment: block.alignment)
        }
    }

    private func paragraph(_ text: AttributedString, alignment: FABlock.Alignment) -> some View {
        Text(text)
            .multilineTextAlignment(alignment.textAlignment)
            .frame(maxWidth: .infinity, alignment: alignment.frameAlignment)
    }

    /// FA's `.bbcode_h1`–`h5`, which are absolute pixel sizes rather than text styles.
    private static func headingPointSize(_ level: Int) -> Double {
        switch level {
        case 1: 26
        case 2: 24
        case 3: 22
        case 4: 20
        default: 18
        }
    }

    /// FA's stylesheet heads its headings in pale blue on the dark theme and in the
    /// plain label colour on the light one; iOS picks the same way, by theme.
    private var headingColor: Color {
        switch colorScheme {
        case .dark:
            Color(faARGB: 0xFFAD_D8F5)
        default:
            Color.primary
        }
    }
}

private extension FABlock.Alignment {
    var textAlignment: TextAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    var frameAlignment: Alignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

extension AttributedString {
    /// FA's parser attributes restated as the SwiftUI ones the Compose bridge reads.
    var styledForDisplay: AttributedString {
        var result = AttributedString()
        for run in runs {
            // Inline images are carried on a U+FFFC placeholder, which draws as a tofu
            // box until there is a renderer for them.
            guard run.faImage == nil else { continue }

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

extension Color {
    init(faARGB argb: UInt32) {
        self.init(
            red: Double((argb >> 16) & 0xFF) / 255,
            green: Double((argb >> 8) & 0xFF) / 255,
            blue: Double(argb & 0xFF) / 255,
            opacity: Double((argb >> 24) & 0xFF) / 255
        )
    }
}
