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

extension FASubmissionPreview: Identifiable {
    public var id: Int { sid }
}

struct SubmissionsFeedView: View {
    @EnvironmentObject var model: Model
    @State private var submissionPreviews = [FASubmissionPreview]()
    @State private var newSubmissionsCount: Int?
    @State private var lastRefreshDate: Date?
    @State private var collectionView: UICollectionView!
    @State private var tableView: UITableView!
    @State private var targetIndexPath: IndexPath?
    
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
    
    func refresh(pulled: Bool) async {
        let latestSubmissions = await model.session?.submissionPreviews() ?? []
        
        let newSubmissions = latestSubmissions
            .filter { !submissionPreviews.contains($0) }
        lastRefreshDate = Date()
        
        guard !newSubmissions.isEmpty else { return }
        
        if var index = centerIndexPath() {
            index.row += newSubmissions.count
            targetIndexPath = index
        }
        
        // The new Task + sleep gives time for the pull-to-refresh to go back
        // to its position and prevents interrupting animation
        Task {
            if pulled {
                try await Task.sleep(nanoseconds: UInt64(0.5e9))
            }
            submissionPreviews.insert(contentsOf: newSubmissions, at: 0)
            withAnimation {
                newSubmissionsCount = newSubmissions.count
            }
        }
    }
    
    func autorefreshIfNeeded() {
        if let lastRefreshDate = lastRefreshDate {
            let secondsSinceLastRefresh = -lastRefreshDate.timeIntervalSinceNow
            guard secondsSinceLastRefresh > 15 * 60 else { return }
        }
        
        Task {
            await refresh(pulled: false)
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
                    await refresh(pulled: true)
                }
                
            }
            .onChange(of: submissionPreviews) { newValue in
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

struct SubmissionsFeedView_Previews: PreviewProvider {
    static var previews: some View {
        SubmissionsFeedView()
            .environmentObject(Model.demo)
            .preferredColorScheme(.dark)
    }
}
