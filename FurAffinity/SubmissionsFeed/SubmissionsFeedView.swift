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
    @State private var currentViewIsDisplayed = false
    
    var body: some View {
        ScrollViewReader { proxy in
            Group {
                if let previews = model.submissionPreviews {
                    List(previews) { submission in
                        NavigationLink(value: FAURL(with: submission.url)) {
                            SubmissionFeedItemView<AuthoredHeaderView>(submission: submission)
                                .id(submission.sid)
                        }
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    }
                    .introspectScrollViewOnList { scrollView in
                        Task {
                            self.scrollView = scrollView
                        }
                    }
                    .listStyle(.plain)
                    .navigationBarTitleDisplayMode(.inline)
                    .overlay(alignment: .topTrailing) {
                        SubmissionsFeedActionView()
                            .padding(.trailing, 20)
                            .padding(.top, 6)
                    }
                    // Toolbar needs to be setup before refresh control…
                    // https://stackoverflow.com/a/64700545/869385
                    .navigationTitle("Submissions")
                    .toolbar(.hidden, for: .navigationBar)
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
            // Relying on this to know if the view is displayed doesn't always work
            // in the general case, hopefully this view is used in a TabView
            // which calls these modifiers as expected!
            .onAppear {
                currentViewIsDisplayed = true
            }
            .onDisappear {
                currentViewIsDisplayed = false
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
                .fetchSubmissionPreviews()
            
            withAnimation {
                newSubmissionsCount = newSubmissionCount
            }
        }
    }
    
    func autorefreshIfNeeded() {
        guard scrollView?.reachedTop ?? true else { return }
        guard currentViewIsDisplayed else { return }
        
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
            SubmissionsFeedView()
                .environmentObject(Model.demo)
            SubmissionsFeedView()
                .environmentObject(Model.empty)
        }
        .preferredColorScheme(.dark)
    }
}
