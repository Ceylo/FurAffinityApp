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
    @State private var lastRefreshDate: Date?
    @State private var collectionView: UICollectionView!
    @State private var tableView: UITableView!
    @State private var targetIndexPath: IndexPath?
    
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
                .introspectTableView { tableView in
                    // For iOS 15 and below
                    self.tableView = tableView
                }
                .introspectCollectionView { collectionView in
                    // For iOS 16 and later
                    self.collectionView = collectionView
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
            .onChange(of: targetIndexPath) { newValue in
                // Preserve currently visible submission after a pull to refresh
                if let targetIndexPath {
                    // Async because at this point the backing UIView doesn't have the new items yet
                    Task {
                        scrollToIndexPath(targetIndexPath)
                    }
                    self.targetIndexPath = nil
                }
            }
        }
        .task {
            autorefreshIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            autorefreshIfNeeded()
        }
    }
}

// MARK: - Scrolling
extension SubmissionsFeedView {
    func centerIndexPath() -> IndexPath? {
        if #available(iOS 16, *) {
            return collectionView.indexPathForItem(at: collectionView.center + collectionView.contentOffset)
        } else {
            return tableView.indexPathForRow(at: tableView.center + tableView.contentOffset)
        }
    }
    
    func scrollToIndexPath(_ indexPath: IndexPath) {
        if #available(iOS 16, *) {
            collectionView.scrollToItem(at: indexPath, at: .top, animated: false)
        } else {
            tableView.scrollToRow(at: indexPath, at: .top, animated: false)
        }
    }
}

// MARK: - Refresh
extension SubmissionsFeedView {
    func refresh(pulled: Bool) async throws {
        // The delay gives time for the pull-to-refresh to go back
        // to its position and prevents interrupting animation
        if pulled {
            try await Task.sleep(nanoseconds: UInt64(0.5 * 1e9))
        }
        
        let visibleIndexPathBeforeRefresh = centerIndexPath()
        let newSubmissionCount = try await model
            .fetchNewSubmissionPreviews()
        lastRefreshDate = Date()
        
        guard newSubmissionCount > 0 else { return }
        
        if var index = visibleIndexPathBeforeRefresh {
            index.row += newSubmissionCount
            targetIndexPath = index
        }
        
        withAnimation {
            newSubmissionsCount = newSubmissionCount
        }
    }
    
    func autorefreshIfNeeded() {
        if let lastRefreshDate = lastRefreshDate {
            let secondsSinceLastRefresh = -lastRefreshDate.timeIntervalSinceNow
            guard secondsSinceLastRefresh > 15 * 60 else { return }
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
