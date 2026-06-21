//
//  SubmissionTextContent.swift
//  FurAffinity
//
//  Created by Ceylo on 21/06/2026.
//

import SwiftUI
import FAKit

/// Renders a text/story submission: a rendered cover page plus a button that
/// downloads the document and opens it in a native reading view. The downloaded
/// file URL is exposed to the parent (for Save/Share) via `documentFileUrl`.
struct SubmissionTextContent: View {
    @Environment(ErrorStorage.self) private var errorStorage

    var title: String
    var textContent: FASubmission.TextContent
    var thumbnail: DynamicThumbnail?
    var previewImageUrl: URL
    @Binding var documentFileUrl: URL?
    var downloadDocument: (_ url: URL) async throws -> Data

    @State private var isDownloading = false
    @State private var readerContent: StoryReaderView.Content?
    /// Extracted once, reused so re-opening doesn't re-download or re-parse.
    @State private var loadedContent: StoryReaderView.Content?

    private var coverUrl: URL {
        textContent.renderedPreviewUrl
    }

    var body: some View {
        VStack(spacing: 12) {
            FAImage(coverUrl)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3))
                }
                .overlay {
                    if isDownloading {
                        ZStack {
                            Color.black.opacity(0.25)
                            ProgressView()
                                .controlSize(.large)
                                .tint(.white)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    readStory()
                }
                .disabled(isDownloading)

            Button {
                readStory()
            } label: {
                HStack {
                    if isDownloading {
                        ProgressView()
                    } else {
                        Image(systemName: "book")
                    }
                    Text(isDownloading ? "Downloading…" : "Read story")
                }
            }
            .controlSize(.large)
            .applying {
                if #available(iOS 26, *) {
                    $0.buttonStyle(.glassProminent)
                } else {
                    $0.buttonStyle(.borderedProminent)
                }
            }
            .disabled(isDownloading)
        }
        .padding(.horizontal, 10)
        .sheet(item: $readerContent) { content in
            StoryReaderView(title: title, content: content)
        }
    }

    private func readStory() {
        if let loadedContent {
            readerContent = loadedContent
            return
        }

        isDownloading = true
        Task {
            await storeLocalizedError(
                in: errorStorage,
                action: "Story Download",
                webBrowserURL: textContent.documentUrl
            ) {
                let data = try await downloadDocument(textContent.documentUrl)
                let fileUrl = FileManager.default.temporaryDirectory
                    .appendingPathComponent(textContent.documentUrl.lastPathComponent)
                try data.write(to: fileUrl, options: .atomic)
                documentFileUrl = fileUrl

                let filename = textContent.documentUrl.lastPathComponent
                let text = await Task.detached {
                    StoryDocument.richText(from: data, filename: filename)
                }.value
                let content: StoryReaderView.Content = text.map { .text($0) } ?? .document(fileUrl)
                loadedContent = content
                readerContent = content
            }
            isDownloading = false
        }
    }
}

#Preview {
    @Previewable
    @State var errorStorage = ErrorStorage()

    withAsync({ () -> (FASubmission.TextContent, URL) in
        let submission = await FASubmission.demoText
        guard case let .text(text) = submission.content else {
            fatalError("demoText must be a text submission")
        }
        return (text, submission.previewImageUrl)
    }) { data in
        SubmissionTextContent(
            title: "Prepared for the Fallout",
            textContent: data.0,
            thumbnail: nil,
            previewImageUrl: data.1,
            documentFileUrl: .constant(nil),
            downloadDocument: { try await OfflineFASession.default.file(at: $0) }
        )
        .environment(errorStorage)
    }
}
