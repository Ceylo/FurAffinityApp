//
//  RemoteSubmissionView.swift
//  FurAffinity
//
//  Created by Ceylo on 21/11/2021.
//

import SwiftUI
import FAKit

struct RemoteSubmissionView: View {
    @EnvironmentObject var model: Model
    
    var url: URL
    var previewData: FASubmissionPreview?
    @State private var avatarUrl: URL?
    @State private var submission: FASubmission?
    @State private var submissionLoadingFailed = false
    @State private var activity: NSUserActivity?
    
    private func loadSubmission(forceReload: Bool) async {
        guard submission == nil || forceReload else {
            return
        }
        
        if let previewData {
            avatarUrl = await model.session?.avatarUrl(for: previewData.author)
        }
        
        submission = await model.session?.submission(for: url)
        if let submission {
            avatarUrl = await model.session?.avatarUrl(for: submission.author)
            submissionLoadingFailed = false
        } else {
            submissionLoadingFailed = true
        }
    }
    
    func loadingSucceededView(_ submission: FASubmission, thumbnailUrl: URL?) -> some View {
        SubmissionView(
            submission: submission,
            avatarUrl: avatarUrl,
            thumbnailUrl: thumbnailUrl,
            favoriteAction: {
                Task {
                    self.submission = try await model.toggleFavorite(for: submission)
                }
            },
            replyAction: { parentCid, text in
                Task {
                    self.submission = try await model
                        .postComment(on: submission,
                                     replytoCid: parentCid,
                                     contents: text)
                }
            })
    }
    
    var body: some View {
        Group {
            if let submission {
                loadingSucceededView(submission, thumbnailUrl: previewData?.thumbnailUrl)
            } else if submissionLoadingFailed {
                ScrollView {
                    LoadingFailedView(url: url)
                }
            } else if let previewData {
                SubmissionPreviewView(submission: previewData, avatarUrl: avatarUrl)
            } else {
                ProgressView()
            }
        }
        .refreshable {
            Task {
                await loadSubmission(forceReload: true)
            }
        }
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

#Preview {
    RemoteSubmissionView(
        url: FASubmissionPreview.demo.url,
        previewData: .demo
    )
//    .preferredColorScheme(.dark)
    .environmentObject(Model.demo)
}
