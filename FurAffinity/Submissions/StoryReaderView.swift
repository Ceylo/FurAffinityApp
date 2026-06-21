//
//  StoryReaderView.swift
//  FurAffinity
//
//  Created by Ceylo on 21/06/2026.
//

import SwiftUI

/// Reads a story submission. Extracted text is rendered as native, reflowing text
/// at the same size as the submission description; formats we can't extract fall
/// back to a QuickLook document preview. Presented in a sheet with a Done button.
struct StoryReaderView: View {
    enum Content: Identifiable {
        case text(AttributedString)
        case document(URL)

        var id: String {
            switch self {
            case .text: "text"
            case .document(let url): url.absoluteString
            }
        }
    }

    var title: String
    var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch content {
                case .text(let text):
                    StoryTextView(attributedText: text)
                        .ignoresSafeArea(edges: .bottom)
                case .document(let url):
                    QuickLookPreview(fileUrl: url)
                        .ignoresSafeArea()
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// A scrollable, read-only `UITextView` rendering the extracted rich text.
/// Run fonts are normalized so the document's dominant size maps to the user's
/// Dynamic Type body size (other sizes scale proportionally), foreground color is
/// forced to `.label` for light/dark, and paragraphs gain spacing for readability.
private struct StoryTextView: UIViewRepresentable {
    var attributedText: AttributedString

    /// Default `.body` point size at the standard content-size category; the
    /// document's dominant run size is mapped to this, then scaled by Dynamic Type.
    private let referenceBodySize: CGFloat = 17

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView(usingTextLayoutManager: true)
        view.isEditable = false
        view.isScrollEnabled = true
        view.backgroundColor = nil
        view.textColor = .label
        view.adjustsFontForContentSizeCategory = true
        view.dataDetectorTypes = [.link]
        view.textContainerInset = .init(top: 12, left: 12, bottom: 12, right: 12)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        view.attributedText = normalized(NSAttributedString(attributedText))
    }

    /// Rescales run fonts relative to the dominant body size and applies paragraph
    /// spacing, wrapping fonts in `UIFontMetrics` so they track Dynamic Type.
    private func normalized(_ source: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: source)
        let full = NSRange(location: 0, length: result.length)

        let bodySize = dominantFontSize(in: result) ?? referenceBodySize
        let metrics = UIFontMetrics(forTextStyle: .body)

        result.enumerateAttribute(.font, in: full) { value, range, _ in
            let font = value as? UIFont ?? .systemFont(ofSize: bodySize)
            let scaled = font.fontDescriptor.withSize(font.pointSize / bodySize * referenceBodySize)
            let base = UIFont(descriptor: scaled, size: scaled.pointSize)
            result.addAttribute(.font, value: metrics.scaledFont(for: base), range: range)
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = metrics.scaledValue(for: referenceBodySize * 0.6)
        paragraph.lineBreakMode = .byWordWrapping
        result.addAttribute(.paragraphStyle, value: paragraph, range: full)

        return result
    }

    /// The run size covering the most characters — treated as the body size.
    private func dominantFontSize(in text: NSAttributedString) -> CGFloat? {
        var lengthBySize: [CGFloat: Int] = [:]
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let font = value as? UIFont else { return }
            lengthBySize[font.pointSize, default: 0] += range.length
        }
        return lengthBySize.max { $0.value < $1.value }?.key
    }
}

#Preview {
    let sample = """
    The vault door groaned open as the wind howled across the wasteland. \
    She tightened her grip on the rifle and stepped into the light.

    Somewhere beyond the dunes, a radio crackled to life — the first voice \
    she had heard in days.
    """

    Color.clear
        .sheet(isPresented: .constant(true)) {
            StoryReaderView(title: "Prepared for the Fallout", content: .text(AttributedString(sample)))
        }
}
