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
        case text(String)
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
                    StoryTextView(text: text)
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

/// A scrollable, read-only `UITextView` matching the submission description's look:
/// dynamic `.body` font and `.label` color, so it adapts to light/dark and
/// Dynamic Type. Mirrors `HTMLView`'s UITextView but scrolls instead of self-sizing.
private struct StoryTextView: UIViewRepresentable {
    var text: String

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView(usingTextLayoutManager: true)
        view.isEditable = false
        view.isScrollEnabled = true
        view.backgroundColor = nil
        view.textColor = .label
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.dataDetectorTypes = [.link]
        view.textContainerInset = .init(top: 12, left: 12, bottom: 12, right: 12)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        view.text = text
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
            StoryReaderView(title: "Prepared for the Fallout", content: .text(sample))
        }
}
