//
//  StoryReaderView+Android.swift
//  FurAffinityUI (Android)
//
//  The Android build of `StoryReaderView`. iOS reflows txt, md, rtf, pdf and docx into a
//  `UITextView` and falls back to QuickLook; here only the plain-text formats are read
//  (`StoryText`), one `Text` per line in a lazy stack so Compose never measures a whole
//  novel at once, and anything else is handed to another app.
//

import SwiftUI
import FAKit

struct StoryReaderView: View {
    struct Content: Identifiable {
        /// The story's lines, or `nil` for formats we can't read.
        var paragraphs: [String]?
        /// The downloaded document on disk.
        var documentUrl: URL

        var id: String { documentUrl.absoluteString }

        static func load(data: Data, filename: String, documentUrl: URL) async -> Content {
            let paragraphs = await Task.detached {
                StoryText.paragraphs(from: data, filename: filename)
            }.value
            return Content(paragraphs: paragraphs, documentUrl: documentUrl)
        }
    }

    var title: String
    var content: Content

    var body: some View {
        NavigationStack {
            Group {
                if let paragraphs = content.paragraphs {
                    ScrollView {
                        // Spacing and line spacing follow the iOS reader's 0.7× and 0.35× of
                        // a 17 pt body.
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(paragraphs.indices, id: \.self) { index in
                                Text(verbatim: paragraphs[index])
                                    .lineSpacing(6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(12)
                    }
                } else {
                    VStack(spacing: 16) {
                        Text("This story's format can't be shown in the app.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        Button("Open in another app") {
                            Task { await MediaBridge.open(fileUrl: content.documentUrl) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
