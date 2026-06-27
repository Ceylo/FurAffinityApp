//
//  SubmissionView.swift
//  FurAffinity
//
//  Created by Ceylo on 30/03/2023.
//

import SwiftUI
import FAKit

struct SubmissionView: View {
    @Environment(ErrorStorage.self) private var errorStorage
    
    var submission: FASubmission
    var avatarUrl: URL?
    var thumbnail: DynamicThumbnail?
    var thumbnailWidthOnHeightRatio: Float?
    var favoriteAction: () -> Void
    var replyAction: @MainActor (_ parentCid: Int?, _ text: CommentReply) async throws -> Void
    var sendNoteAction: (_ destinationUser: String, _ subject: String, _ text: String) async throws -> Void
    var downloadDocument: (_ url: URL) async throws -> Data
    
    struct ReplySession {
        let parentCid: Int?
    }
    @State private var replySession: CommentReplySession?
    @State private var fullResolutionMediaFileUrl: URL?
    @State private var documentFileUrl: URL?
    @State private var noteReplySession: NoteReplySession?
    @State private var audioController: AudioPlaybackController?

    /// True for content kinds saved as a document (to Files) rather than an
    /// image (to Photos): text and audio.
    private var savesToFiles: Bool {
        switch submission.content {
        case .text, .audio: return true
        case .image: return false
        }
    }

    /// The downloaded file backing Save/Share, whichever content kind applies.
    private var savableFileUrl: URL? {
        savesToFiles ? documentFileUrl : fullResolutionMediaFileUrl
    }

    private var imageResolution: String? {
        if case let .image(image) = submission.content { return image.resolution }
        return nil
    }

    var header: some View {
        TitleAuthorHeader(
            username: submission.author,
            displayName: submission.displayAuthor,
            title: submission.title,
            datetime: .init(submission.datetime,
                            submission.naturalDatetime)
        )
        .padding(.horizontal, 10)
    }
    
    @ViewBuilder
    var mainContent: some View {
        switch submission.content {
        case let .image(image):
            SubmissionMainImage(
                widthOnHeightRatio: image.widthOnHeightRatio,
                thumbnailImage: thumbnail,
                fullResolutionMediaUrl: image.mediaUrl,
                fullResolutionMediaFileUrl: $fullResolutionMediaFileUrl
            )
        case let .text(text):
            SubmissionTextContent(
                title: submission.title,
                textContent: text,
                thumbnail: thumbnail,
                previewImageUrl: submission.previewImageUrl,
                documentFileUrl: $documentFileUrl,
                downloadDocument: downloadDocument
            )
        case let .audio(audio):
            SubmissionAudioContent(
                audioContent: audio,
                title: submission.title,
                author: submission.author,
                thumbnail: thumbnail,
                thumbnailWidthOnHeightRatio: thumbnailWidthOnHeightRatio,
                controller: $audioController,
                documentFileUrl: $documentFileUrl,
                downloadDocument: downloadDocument
            )
        }
    }

    var submissionControls: some View {
        SubmissionControlsView(
            submissionUrl: submission.url,
            mediaFileUrl: savableFileUrl,
            savesToFiles: savesToFiles,
            favoritesCount: submission.favoriteCount,
            isFavorite: submission.isFavorite,
            favoriteAction: favoriteAction,
            repliesCount: submission.comments.recursiveCount,
            acceptsNewReplies: submission.acceptsNewComments,
            replyAction: {
                replySession = .init(parentCid: nil, among: [])
            },
            metadataTarget: .submissionMetadata(submission.metadata, resolution: imageResolution),
            errorStorage: errorStorage
        )
        .padding(.horizontal, 10)
    }
    
    var submissionDescription: some View {
        HTMLView(
            text: submission.description.convertingLinksForInAppNavigation(),
            initialHeight: 300
        )
    }
    
    @ViewBuilder
    var submissionComments: some View {
        if !submission.comments.isEmpty {
            Section {
                CommentsView(
                    comments: submission.comments,
                    highlightedCommentId: submission.targetCommentId,
                    acceptsNewReplies: submission.acceptsNewComments,
                    replyAction: { cid in
                        replySession = .init(parentCid: cid, among: submission.comments)
                    }
                )
            } header: {
                SectionHeader(text: "Comments")
            }
        }
    }
    
    var body: some View {
        List {
            Group {
                header
                mainContent
                submissionControls
                // When glass effect is used in a list with light mode, shadow gets clipped.
                // This padding is a workaround to prevent clipping.
                // It would not happen if using a ScrollView instead of a list,
                // but we'd then lose swipe actions.
                    .padding(.bottom, 30)
                submissionDescription
                submissionComments
            }
            .listRowSeparator(.hidden)
            .listRowInsets(.init(top: 5, leading: 0, bottom: 5, trailing: 0))
        }
        .commentSheet(on: $replySession, replyAction)
        .navigationTitle(submission.title)
        .listStyle(.plain)
        .autoFocusingDeepHighlight(
            in: submission.comments,
            targetCid: submission.targetCommentId,
            acceptsNewReplies: submission.acceptsNewComments,
            replyAction: { cid in
                replySession = .init(parentCid: cid, among: submission.comments)
            }
        )
        .onAppear {
            prefetchAvatars(for: submission.comments)
        }
        .scrollToItem(id: submission.targetCommentId)
        .toolbar {
            RemoteContentToolbarItem(url: submission.url) {
                Button {
                    favoriteAction()
                } label: {
                    let title = submission.isFavorite ? "Unfavorite" : "Favorite"
                    let image = submission.isFavorite ? "heart.fill" : "heart"
                    Label(title, systemImage: image)
                }
                
                Button {
                    if savesToFiles {
                        exportToFiles([savableFileUrl!])
                    } else {
                        Task {
                            await MediaSaveHandler(errorStorage: errorStorage).saveMedia(atFileUrl: savableFileUrl!)
                        }
                    }
                } label: {
                    Label(savesToFiles ? "Save to Files" : "Save Image", systemImage: "square.and.arrow.down")
                }
                .disabled(savableFileUrl == nil)

                Button {
                    share([savableFileUrl!])
                } label: {
                    Label(savesToFiles ? "Share" : "Share Image", systemImage: "square.and.arrow.up")
                }
                .disabled(savableFileUrl == nil)
                
                Button {
                    replySession = .init(parentCid: nil, among: [])
                } label: {
                    Label("Comment", systemImage: "bubble")
                }
                .disabled(!submission.acceptsNewComments)
                
                Button {
                    noteReplySession = .init(defaultContents: .init(
                        destinationUser: submission.author
                    ))
                } label: {
                    Label("Send a Note", systemImage: "message")
                }
            }
        }
        .noteReplySheet(on: $noteReplySession) { reply in
            try await sendNoteAction(reply.destinationUser, reply.subject, reply.text)
        }
    }
}

#Preview("Image submission") {
    @Previewable
    @State var errorStorage = ErrorStorage()
    
    NavigationStack {
        withAsync({ await FASubmission.demoImage }) {
            SubmissionView(
                submission: $0,
                avatarUrl: FAURLs.avatarUrl(for: $0.author),
                favoriteAction: {},
                replyAction: { _, _ in },
                sendNoteAction: { _, _, _ in },
                downloadDocument: { try await OfflineFASession.default.file(at: $0) }
            )
        }
    }
    .environment(errorStorage)
}

#Preview("Text submission") {
    @Previewable
    @State var errorStorage = ErrorStorage()
    
    NavigationStack {
        withAsync({ await FASubmission.demoText }) {
            SubmissionView(
                submission: $0,
                avatarUrl: FAURLs.avatarUrl(for: $0.author),
                favoriteAction: {},
                replyAction: { _, _ in },
                sendNoteAction: { _, _, _ in },
                downloadDocument: { try await OfflineFASession.default.file(at: $0) }
            )
        }
    }
    .environment(errorStorage)
}

#Preview("Audio submission") {
    @Previewable
    @State var errorStorage = ErrorStorage()
    
    NavigationStack {
        withAsync({ await FASubmission.demoAudio }) {
            SubmissionView(
                submission: $0,
                avatarUrl: FAURLs.avatarUrl(for: $0.author),
                favoriteAction: {},
                replyAction: { _, _ in },
                sendNoteAction: { _, _, _ in },
                downloadDocument: { try await OfflineFASession.default.file(at: $0) }
            )
        }
    }
    .environment(errorStorage)
}
