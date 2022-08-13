//
//  SubmissionsFeedView.swift
//  FurAffinity
//
//  Created by Ceylo on 13/11/2021.
//

import SwiftUI
import FAKit

extension FASubmissionPreview: Identifiable {
    public var id: Int { sid }
}

struct SubmissionsFeedView: View {
    @EnvironmentObject var model: Model
    @State private var submissionPreviews = [FASubmissionPreview]()
    @State private var targetScrollItemSid: Int?
    @State private var newSubmissionsCount: Int?
    @State private var lastRefreshDate = Date()
    
    func refresh(pulled: Bool, notify: Bool) async {
        targetScrollItemSid = submissionPreviews.first?.sid
        let latestSubmissions = await model.session?.submissionPreviews() ?? []
        
        let newSubmissions = latestSubmissions
            .filter { !submissionPreviews.contains($0) }
        lastRefreshDate = Date()
        
        guard !newSubmissions.isEmpty else { return }
        
        // The new Task + sleep gives time for the pull-to-refresh to go back
        // to its position and prevents interrupting animation
        Task {
            if pulled {
                try await Task.sleep(nanoseconds: UInt64(0.5e9))
            }
            submissionPreviews.insert(contentsOf: newSubmissions, at: 0)
            if notify {
                withAnimation {
                    newSubmissionsCount = newSubmissions.count
                }
            }
        }
    }
    
    func autorefreshIfNeeded() {
        let secondsSinceLastRefresh = -lastRefreshDate.timeIntervalSinceNow
        guard secondsSinceLastRefresh > 15 * 60 else { return }
        
        Task {
            await refresh(pulled: false, notify: true)
        }
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            NavigationView {
                List(submissionPreviews) { submission in
                    NavigationLink(destination: SubmissionView(model, preview: submission)) {
                        SubmissionFeedItemView(submission: submission)
                            .id(submission.sid)
                    }
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
                .listStyle(.plain)
                .navigationBarTitleDisplayMode(.inline)
                .overlay(alignment: .top) {
                    NotificationOverlay(itemCount: $newSubmissionsCount)
                        .offset(y: 40)
                }
            }
            .task {
                await refresh(pulled: false, notify: false)
            }
            .refreshable {
                await refresh(pulled: true, notify: true)
            }
            .onChange(of: submissionPreviews) { newValue in
                // Preserve currently visible submission after a pull to refresh
                if let targetSid = targetScrollItemSid {
                    proxy.scrollTo(targetSid, anchor: .top)
                    targetScrollItemSid = nil
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                autorefreshIfNeeded()
            }
        }
    }
}

struct SubmissionsFeedView_Previews: PreviewProvider {
    static var previews: some View {
        SubmissionsFeedView()
            .environmentObject(Model.demo)
            .preferredColorScheme(.dark)
    }
}
