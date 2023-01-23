//
//  SubmissionView.swift
//  FurAffinity
//
//  Created by Ceylo on 21/11/2021.
//

import SwiftUI
import URLImage
import FAKit
import Foundation
import Zoomable

struct SubmissionView: View {
    @EnvironmentObject var model: Model
    
    var preview: FASubmissionPreview
    var submissionProvider: () async -> FASubmission?
    @State private var avatarUrl: URL?
    @State private var submission: FASubmission?
    @State private var submissionLoadingFailed = false
    @State private var fullResolutionCGImage: CGImage?
    @State private var description: AttributedString?
    @State private var activity: NSUserActivity?
    
    struct ReplySession {
        let submission: FASubmission
        let parentCid: Int?
    }
    @State private var replySession: ReplySession?
    
    func header(submission: FASubmissionPreview) -> some View {
        SubmissionHeaderView(author: submission.displayAuthor,
                             title: submission.title,
                             avatarUrl: avatarUrl)
            .task {
                avatarUrl = await model.session?.avatarUrl(for: submission.author)
            }
    }
    
    func loadingSucceededView(_ submission: FASubmission) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header(submission: preview)
                SubmissionMainImage(
                    widthOnHeightRatio: preview.thumbnailWidthOnHeightRatio,
                    fullResolutionImageUrl: submission.fullResolutionImageUrl,
                    fullResolutionCGImage: $fullResolutionCGImage
                )
                
                SubmissionControlsView(
                    submissionUrl: submission.url,
                    fullResolutionImage: fullResolutionCGImage,
                    isFavorite: submission.isFavorite,
                    favoriteAction: {
                        Task {
                            self.submission = try await model.toggleFavorite(for: submission)
                        }
                    }, replyAction: {
                        replySession = .init(
                            submission: submission,
                            parentCid: nil
                        )
                    }
                )
                
                if let description = description {
                    TextView(text: description)
                }
                
                SubmissionCommentsView(
                    comments: submission.comments,
                    replyAction: { cid in
                        replySession = .init(
                            submission: submission,
                            parentCid: cid
                        )
                    }
                )
            }
            .padding(10)
        }
        .refreshable {
            Task {
                await loadSubmission()
            }
        }
        .sheet(isPresented: showCommentEditor) {
            commentEditor
        }
    }
    
    private func loadSubmission() async {
        submission = await submissionProvider()
        if let submission = submission {
            description = AttributedString(FAHTML: submission.htmlDescription)
            submissionLoadingFailed = false
        } else {
            submissionLoadingFailed = true
        }
    }
    
    var body: some View {
        ZStack {
            if let submission = submission {
                loadingSucceededView(submission)
            } else if submissionLoadingFailed {
                SubmissionLoadingFailedView(preview: preview)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadSubmission()
        }
        .onAppear {
            if activity == nil {
                let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
                activity.title = preview.title
                activity.webpageURL = preview.url
                self.activity = activity
            }
            
            activity?.becomeCurrent()
        }
        .onDisappear {
            activity?.resignCurrent()
        }
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
                Task {
                    self.submission = try await model
                        .postComment(on: replySession.submission,
                                     replytoCid: replySession.parentCid,
                                     contents: text)
                }
            }
            self.replySession = nil
        }
    }
}

// MARK: -
extension SubmissionView {
    init(_ model: Model, preview: FASubmissionPreview) {
        self.init(preview: preview) {
            await model.session?.submission(for: preview)
        }
    }
}

struct SubmissionView_Previews: PreviewProvider {
    static var previews: some View {
        SubmissionView(preview: OfflineFASession.default.submissionPreviews[0],
                       submissionProvider: { FASubmission.demo })
            .preferredColorScheme(.dark)
            .environmentObject(Model.demo)
        
        SubmissionView(preview: OfflineFASession.default.submissionPreviews[0],
                       submissionProvider: { nil })
            .preferredColorScheme(.dark)
            .environmentObject(Model.demo)
    }
}
