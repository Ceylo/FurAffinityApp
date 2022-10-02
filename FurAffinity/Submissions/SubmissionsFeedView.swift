//
//  SubmissionsFeedView.swift
//  FurAffinity
//
//  Created by Ceylo on 13/11/2021.
//

import SwiftUI
import FAKit
import Introspect
import UIKit

struct SubmissionsFeedView: View {
    @EnvironmentObject var model: Model
    @State private var newSubmissionsCount: Int?
    @State private var scrollView: UIScrollView?
    @State private var targetScrollItemSid: Int?
    
    var body: some View {
        ScrollViewReader { proxy in
            NavigationView {
                List(model.submissionPreviews) { submission in
                    NavigationLink(destination: SubmissionView(model, preview: submission)) {
                        SubmissionFeedItemView(submission: submission)
                            .id(submission.sid)
                    }
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
                .introspectScrollViewOnList { scrollView in
                    self.scrollView = scrollView
                }
                .listStyle(.plain)
                .navigationBarTitleDisplayMode(.inline)
                .overlay(alignment: .top) {
                    NotificationOverlay(itemCount: $newSubmissionsCount)
                        .offset(y: 40)
                }
                .refreshable {
                    try? await refresh(pulled: true)
                }
            }
            .onChange(of: model.submissionPreviews) { newValue in
                Task { @MainActor in
                    if let targetSid = targetScrollItemSid {
                        proxy.scrollTo(targetSid, anchor: .top)
                        targetScrollItemSid = nil
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            autorefreshIfNeeded()
        }
    }
}

// MARK: - Refresh
extension SubmissionsFeedView {
    func refresh(pulled: Bool) async throws {
        targetScrollItemSid = model.submissionPreviews.first?.sid
        
        // The delay gives time for the pull-to-refresh to go back
        // to its position and prevents interrupting animation
        if pulled {
            try await Task.sleep(nanoseconds: UInt64(0.5 * 1e9))
        }
        
        let newSubmissionCount = await model
            .fetchNewSubmissionPreviews()
        
        guard newSubmissionCount > 0 else { return }
                
        withAnimation {
            newSubmissionsCount = newSubmissionCount
        }
    }
    
    func autorefreshIfNeeded() {
        guard scrollView?.reachedTop ?? true else { return }
        
        if let lastRefreshDate = model.lastSubmissionPreviewsFetchDate {
            let secondsSinceLastRefresh = -lastRefreshDate.timeIntervalSinceNow
            guard secondsSinceLastRefresh > Model.autorefreshDelay else { return }
        }
        
        Task {
            try await refresh(pulled: false)
        }
    }
}

// MARK: -
struct SubmissionsFeedView_Previews: PreviewProvider {
    static var previews: some View {
        SubmissionsFeedView()
            .environmentObject(Model.demo)
            .preferredColorScheme(.dark)
    }
}
