//
//  SubmissionTextContent.swift
//  FurAffinity
//
//  Created by Ceylo on 21/06/2026.
//

import SwiftUI
import FAKit

/// Renders a text/story submission: a rendered cover page plus a button that
/// downloads the document and opens it in QuickLook. The downloaded file URL is
/// exposed to the parent (for Save/Share) via `documentFileUrl`.
struct SubmissionTextContent: View {
    @Environment(Model.self) private var model
    @Environment(ErrorStorage.self) private var errorStorage

    var textContent: FASubmission.TextContent
    var thumbnail: DynamicThumbnail?
    var previewImageUrl: URL
    @Binding var documentFileUrl: URL?

    @State private var isDownloading = false
    @State private var showPreview = false

    private var coverUrl: URL {
        textContent.renderedPreviewUrl
    }

    var body: some View {
        VStack(spacing: 16) {
            FAImage(coverUrl)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3))
                }

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
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isDownloading)
        }
        .padding(.horizontal, 10)
        .sheet(isPresented: $showPreview) {
            if let documentFileUrl {
                QuickLookPreview(fileUrl: documentFileUrl)
                    .ignoresSafeArea()
            }
        }
    }

    private func readStory() {
        if documentFileUrl != nil {
            showPreview = true
            return
        }

        guard let session = model.session else { return }
        isDownloading = true
        Task {
            await storeLocalizedError(
                in: errorStorage,
                action: "Story Download",
                webBrowserURL: textContent.documentUrl
            ) {
                let data = try await session.file(at: textContent.documentUrl)
                let fileUrl = FileManager.default.temporaryDirectory
                    .appendingPathComponent(textContent.documentUrl.lastPathComponent)
                try data.write(to: fileUrl, options: .atomic)
                documentFileUrl = fileUrl
                showPreview = true
            }
            isDownloading = false
        }
    }
}

#Preview {
    withAsync({ () -> (Model, FASubmission.TextContent, URL) in
        let model = try await Model.demo
        let submission = await FASubmission.demoText
        guard case let .text(text) = submission.content else {
            fatalError("demoText must be a text submission")
        }
        return (model, text, submission.previewImageUrl)
    }) { data in
        SubmissionTextContent(
            textContent: data.1,
            thumbnail: nil,
            previewImageUrl: data.2,
            documentFileUrl: .constant(nil)
        )
        .environment(data.0)
        .environment(data.0.errorStorage)
    }
}
