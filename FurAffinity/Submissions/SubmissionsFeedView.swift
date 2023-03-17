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
    @Binding var navigationStack: NavigationPath
    @State private var newSubmissionsCount: Int?
    @State private var scrollView: UIScrollView?
    @State private var targetScrollItemSid: Int?
    
    var body: some View {
        ScrollViewReader { proxy in
            NavigationStack(path: $navigationStack) {
                if let previews = model.submissionPreviews {
                    List(previews) { submission in
                        NavigationLink(value: FAURL(with: submission.url)) {
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
                    .overlay(alignment: .topTrailing) {
                        SubmissionsFeedActionView()
                            .padding(.trailing, 20)
                            .padding(.top, 6)
                    }
                    .refreshable {
                        refresh(pulled: true)
                    }
                    .swap(when: previews.isEmpty) {
                        VStack(spacing: 20) {
                            VStack(spacing: 10) {
                                Text("It's a bit empty in here.")
                                    .font(.headline)
                                Text("Watch artists and wait for them to post new art. Submissions from [www.furaffinity.net/msg/submissions/](https://www.furaffinity.net/msg/submissions/) will be displayed here.")
                                    .multilineTextAlignment(.center)
                                    .foregroundColor(.secondary)
                            }
                            
                            Button("Refresh") {
                                refresh(pulled: true)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationDestination(for: FAURL.self) { nav in
                switch nav {
                case let .submission(url):
                    SubmissionView(url: url)
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
            .overlay(alignment: .top) {
                NotificationOverlay(itemCount: $newSubmissionsCount)
                    .offset(y: 40)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                autorefreshIfNeeded()
            }
        }
    }
}

// MARK: - Refresh
extension SubmissionsFeedView {
    func refresh(pulled: Bool) {
        targetScrollItemSid = model.submissionPreviews?.first?.sid
        
        Task {
            // The delay gives time for the pull-to-refresh to go back
            // to its position and prevents interrupting animation
            if pulled {
                try await Task.sleep(nanoseconds: UInt64(0.5 * 1e9))
            }
            
            let newSubmissionCount = await model
                .fetchNewSubmissionPreviews()
            
            withAnimation {
                newSubmissionsCount = newSubmissionCount
            }
        }
    }
    
    func autorefreshIfNeeded() {
        guard scrollView?.reachedTop ?? true else { return }
        
        if let lastRefreshDate = model.lastSubmissionPreviewsFetchDate {
            let secondsSinceLastRefresh = -lastRefreshDate.timeIntervalSinceNow
            guard secondsSinceLastRefresh > Model.autorefreshDelay else { return }
        }
        
        refresh(pulled: false)
    }
}

// MARK: -
struct SubmissionsFeedView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SubmissionsFeedView(navigationStack: .constant(NavigationPath()))
                .environmentObject(Model.demo)
            SubmissionsFeedView(navigationStack: .constant(NavigationPath()))
                .environmentObject(Model.empty)
        }
        .preferredColorScheme(.dark)
    }
}
