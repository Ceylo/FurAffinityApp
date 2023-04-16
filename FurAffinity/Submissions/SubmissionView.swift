//
//  SubmissionView.swift
//  FurAffinity
//
//  Created by Ceylo on 30/03/2023.
//

import SwiftUI
import FAKit

struct SubmissionView: View {
    var submission: FASubmission
    var avatarUrl: URL?
    var description: AttributedString?
    var favoriteAction: () -> Void
    var replyAction: (_ parentCid: Int?, _ text: String) -> Void
    
    struct ReplySession {
        let parentCid: Int?
    }
    @State private var replySession: ReplySession?
    @State private var fullResolutionCGImage: CGImage?
    
    var header: some View {
        SubmissionHeaderView(
            username: submission.author,
            displayName: submission.displayAuthor,
            title: submission.title,
            avatarUrl: avatarUrl,
            datetime: .init(submission.datetime,
                            submission.naturalDatetime)
        )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            SubmissionMainImage(
                widthOnHeightRatio: submission.widthOnHeightRatio,
                fullResolutionImageUrl: submission.fullResolutionImageUrl,
                fullResolutionCGImage: $fullResolutionCGImage
            )
            
            SubmissionControlsView(
                submissionUrl: submission.url,
                fullResolutionImage: fullResolutionCGImage,
                isFavorite: submission.isFavorite,
                favoriteAction: favoriteAction,
                replyAction: {
                    replySession = .init(parentCid: nil)
                }
            )
            
            if let description {
                TextView(text: description, initialHeight: 300)
            }
            
            CommentsView(
                comments: submission.comments,
                replyAction: { cid in
                    replySession = .init(parentCid: cid)
                }
            )
        }
        .padding(10)
        .sheet(isPresented: showCommentEditor) {
            commentEditor
        }
        .navigationTitle(submission.title)
    }
}

// MARK: - Comment replies
extension SubmissionView {
    var showCommentEditor: Binding<Bool> {
        .init {
            replySession != nil
        } set: { value in
            if value {
                fatalError()
            } else {
                replySession = nil
            }
        }
    }
    
    private var commentEditor: some View {
        guard let replySession else {
            fatalError()
        }
        
        return CommentEditor { text in
            if let text {
                replyAction(replySession.parentCid, text)
            }
            self.replySession = nil
        }
    }
}

struct SubmissionView_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            SubmissionView(
                submission: FASubmission.demo,
                favoriteAction: {},
                replyAction: { parentCid,text in }
            )
        }
    }
}
