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

        var id: String { documentUrl.absoluteString }

        static func load(data: Data, documentUrl: URL) async -> Content {
            let filename = documentUrl.lastPathComponent
            let pdfPages = documentUrl.pathExtension.lowercased() == "pdf"
                ? await PDFTextBridge.pages(fileUrl: documentUrl) : nil
            let paragraphs = await Task.detached {
                StoryDocument.paragraphs(from: data, filename: filename, pdfPages: { _ in pdfPages })
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
                    let scale = StoryParagraphView.bodySize / (paragraphs.dominantFontSize ?? StoryParagraphView.bodySize)
                    ScrollView {
                        // Spacing and line spacing follow the iOS reader's 0.7× and 0.35× of
                        // a 17 pt body.
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(paragraphs.indices, id: \.self) { index in
                                StoryParagraphView(paragraph: paragraphs[index], scale: scale)
                            }
                        }
                        .padding(12)
                    }
                } else {
                    VStack(spacing: 16) {
                        Text("This story's format can't be shown in the app.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        Button("Open in another app", action: openInAnotherApp)
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if content.paragraphs != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: openInAnotherApp) {
                            // SkipUI maps no symbol to "arrow.up.forward.app"; this is its
                            // Material counterpart.
                            Label("Open in Another App", systemImage: "Icons.Outlined.ExitToApp")
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
    static let bodySize: CGFloat = 17

    var paragraph: StoryParagraph
    var scale: CGFloat

    var body: some View {
        if let png = paragraph.image, let image = UIImage(data: png) {
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
        var lengthBySize: [CGFloat: Int] = [:]
        for run in paragraph.runs { lengthBySize[run.font.size, default: 0] += run.text.count }
        let size = lengthBySize.max { $0.value < $1.value }?.key ?? Self.bodySize / scale
        return size * scale
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
            if run.font.italic { html = "<i>\(html)</i>" }
            if run.font.bold { html = "<b>\(html)</b>" }
            return html
        }.joined())
        #else
        return Text(verbatim: runs.map(\.text).joined())
        #endif
    }
}
