//
//  StoryReaderView+Android.swift
//  FurAffinityUI (Android)
//
//  The Android build of `StoryReaderView`. Both platforms extract the story with FAKit's
//  `StoryDocument`; here each paragraph is one `Text` in a lazy stack, so Compose never
//  measures a whole novel at once.
//

import SwiftUI
import FAKit

struct StoryReaderView: View {
    struct Content: Identifiable {
        /// The story's paragraphs, or `nil` for formats we can't read.
        var paragraphs: [StoryParagraph]?
        /// The downloaded document on disk.
        var documentUrl: URL
        var scale: CGFloat = 1
        let images = DecodedImages()

        var id: String { documentUrl.absoluteString }

        static func load(data: Data, documentUrl: URL) async -> Content {
            let filename = documentUrl.lastPathComponent
            let pdfPages = documentUrl.pathExtension.lowercased() == "pdf"
                ? await PDFTextBridge.pages(fileUrl: documentUrl) : nil
            let paragraphs = await Task.detached {
                StoryDocument.paragraphs(from: data, filename: filename, pdfPages: pdfPages)
            }.value
            var content = Content(paragraphs: paragraphs, documentUrl: documentUrl)
            if let size = paragraphs?.dominantFontSize {
                content.scale = StoryParagraphView.bodySize / size
            }
            return content
        }
    }

    // Not private: skipstone can't bridge a private @State/@Environment.
    @Environment(\.dismiss) var dismiss

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
                                StoryParagraphView(
                                    paragraph: paragraphs[index],
                                    image: paragraphs[index].image.flatMap { content.images.image(at: index, png: $0) },
                                    scale: content.scale
                                )
                            }
                        }
                        .padding(12)
                    }
                } else {
                    VStack(spacing: 16) {
                        Text("This story's format can't be shown in the app.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        Button("Open with…", action: openInAnotherApp)
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .onAppear { OrientationBridge.allowLandscape(true) }
            .onDisappear { OrientationBridge.allowLandscape(false) }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
                if content.paragraphs != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Open with…", action: openInAnotherApp)
                        } label: {
                            ActionControl()
                        }
                    }
                }
            }
        }
    }

    private func openInAnotherApp() {
        Task { await MediaBridge.open(fileUrl: content.documentUrl) }
    }
}

struct StoryParagraphView: View {
    nonisolated static let bodySize: CGFloat = 17

    var paragraph: StoryParagraph
    var image: UIImage?
    var scale: CGFloat

    var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: image.size.width)
                .frame(maxWidth: .infinity)
        } else {
            text
                .font(.system(size: size))
                .lineSpacing(6)
                .multilineTextAlignment(paragraph.centered ? .center : .leading)
                .frame(maxWidth: .infinity, alignment: paragraph.centered ? .center : .leading)
        }
    }

    private var size: CGFloat {
        paragraph.dominantFontSize.map { $0 * scale } ?? Self.bodySize
    }

    private var runs: [StoryRun] {
        var runs = paragraph.runs
        if let first = runs.first, first.text.hasPrefix("\t") {
            let tabs = first.text.prefix { $0 == "\t" }.count
            runs[0].text = String(repeating: "\u{2003}\u{2003}", count: tabs) + first.text.dropFirst(tabs)
        }
        return runs
    }

    private var text: Text {
        let runs = runs
        let bold = Set(runs.map(\.font.bold))
        let italic = Set(runs.map(\.font.italic))
        guard bold.count > 1 || italic.count > 1 else {
            return Text(verbatim: runs.map(\.text).joined())
                .bold(bold.first ?? false)
                .italic(italic.first ?? false)
        }
        #if canImport(Android)
        return Text(html: runs.map { run in
            var html = run.text
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                // HTML collapses runs of spaces; plain paragraphs keep them.
                .replacingOccurrences(of: "  ", with: " &nbsp;")
            if run.font.italic { html = "<i>\(html)</i>" }
            if run.font.bold { html = "<b>\(html)</b>" }
            return html
        }.joined())
        #else
        return Text(verbatim: runs.map(\.text).joined())
        #endif
    }
}

/// Image paragraphs decode on first display, once: each decode is a JNI round trip, and a
/// comic can hold dozens.
final class DecodedImages: @unchecked Sendable {
    private var images: [Int: UIImage] = [:]

    @MainActor
    func image(at index: Int, png: Data) -> UIImage? {
        if let image = images[index] { return image }
        let image = UIImage(data: png)
        images[index] = image
        return image
    }
}
