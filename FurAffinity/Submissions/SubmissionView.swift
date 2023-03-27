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
    
    var url: URL
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
    
    func header(submission: FASubmission) -> some View {
        SubmissionHeaderView(username: submission.author,
                             displayName: submission.displayAuthor,
                             title: submission.title,
                             avatarUrl: avatarUrl,
                             datetime: .init(submission.datetime,
                                             submission.naturalDatetime))
            .task {
                avatarUrl = await model.session?.avatarUrl(for: submission.author)
            }
    }
    
    func loadingSucceededView(_ submission: FASubmission) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header(submission: submission)
                SubmissionMainImage(
                    widthOnHeightRatio: submission.widthOnHeightRatio,
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
                
                if let description {
                    TextView(text: description, initialHeight: 300)
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
                await loadSubmission(forceReload: true)
            }
        }
        .sheet(isPresented: showCommentEditor) {
            commentEditor
        }
        .navigationTitle(submission.title)
    }
    
    private func loadSubmission(forceReload: Bool) async {
        guard submission == nil || forceReload else {
            return
        }
        
        submission = await model.session?.submission(for: url)
        if let submission = submission {
            description = AttributedString(FAHTML: submission.htmlDescription)?
                .convertingLinksForInAppNavigation()
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
                LoadingFailedView(url: url)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadSubmission(forceReload: false)
        }
        .toolbar {
            ToolbarItem {
                Link(destination: url) {
                    Image(systemName: "safari")
                }
            }
        }
        .onAppear {
            if activity == nil {
                let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
                activity.webpageURL = url
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

struct SubmissionView_Previews: PreviewProvider {
    static var previews: some View {
        SubmissionView(url: FASubmissionPreview.demo.url)
            .preferredColorScheme(.dark)
            .environmentObject(Model.demo)
    }
}
