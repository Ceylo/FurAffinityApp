//
//  SubmissionsFeedView.swift
//  FurAffinity
//
//  Created by Ceylo on 13/11/2021.
//

import SwiftUI
import FAKit
@_spi(Advanced) import SwiftUIIntrospect
import UIKit
import Defaults
import Collections

struct SubmissionsFeedView: View {
    @Environment(Model.self) private var model
    @Environment(ErrorStorage.self) private var errorStorage
    @State private var newSubmissionsCount: Int?
    @Weak private var scrollView: UIScrollView?
    @State private var targetScrollItem: FASubmissionPreview?
    @State private var currentViewIsDisplayed = false
    @State private var refreshTask: Task<Void, Never>?
    @State private var pendingAutorefresh = false
    
    var noPreview: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("No submission to display yet.")
                    .font(.headline)
                Text("Watch artists and wait for them to post new art. Submissions from [www.furaffinity.net/msg/submissions/](https://www.furaffinity.net/msg/submissions/) will be displayed here.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                Text("You may pull to refresh.")
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .refreshable {
            refresh(pulled: true)
        }
    }
    
    private enum Item: Hashable, Identifiable {
        case fetchTrigger(targetScrollItem: FASubmissionPreview)
        case submissionPreview(FASubmissionPreview)
        
        var id: Self { self }
    }
    
    private var listItems: [Item]? {
        guard let modelPreviews = model.submissionPreviews else {
            return nil
        }
        
        guard let targetScrollItem else {
            return modelPreviews.map { .submissionPreview($0) }
        }
        
        var items = [Item]()
        for preview in modelPreviews {
            if preview == targetScrollItem {
                items.append(.fetchTrigger(targetScrollItem: targetScrollItem))
            }
            items.append(.submissionPreview(preview))
        }
        return items
    }
    
    /// This implements the most reliable way known to be able to update the list
    /// with new items at the beginning, while preventing the list from scrolling away
    /// of `targetScrollItem`.
    private func fetchTriggerView(with targetPreview: FASubmissionPreview, scrollProxy: ScrollViewProxy) -> some View {
        Rectangle()
            .foregroundStyle(.clear)
            .frame(height: 1)
            .onAppear {
                scrollProxy.scrollTo(Item.submissionPreview(targetPreview), anchor: .top)

                refreshTask = Task {
                    do {
                        try await fetchSubmissionPreviews()
                        self.targetScrollItem = nil
                    } catch {
                        // A fetch cancelled because the feed got covered by a
                        // navigation push must abort silently: don't surface an
                        // error and don't commit the refresh (leave the scroll
                        // choreography untouched so it can re-run on return).
                        if Self.isCancellation(error) { return }
                        storeError(error, in: errorStorage, action: "Submissions Refresh", webBrowserURL: FAURLs.submissionsUrl)
                        self.targetScrollItem = nil
                    }
                }
            }
            .onDisappear {
                scrollProxy.scrollTo(Item.submissionPreview(targetPreview), anchor: .top)
                Defaults[.lastViewedSubmissionID] = targetPreview.sid
            }
    }
    
    private func followItem(_ preview: FASubmissionPreview, frame: CGRect?, geometry: GeometryProxy) {
        guard let frame else { return }
        let listFrame = geometry.frame(in: .global)
        let itemTop = frame.minY / listFrame.height
        let itemBottom = frame.maxY / listFrame.height
        let isActive = (itemTop...itemBottom).contains(0.3)
        if isActive {
            Defaults[.lastViewedSubmissionID] = preview.sid
        }
    }
    
    @ViewBuilder
    private func itemView(for item: Item, geometry: GeometryProxy, scrollProxy: ScrollViewProxy) -> some View {
        switch item {
        case let .fetchTrigger(targetScrollItem):
            fetchTriggerView(with: targetScrollItem, scrollProxy: scrollProxy)
        case let .submissionPreview(preview):
            SubmissionPreviewRow(preview: preview)
                .onItemFrameChanged(listGeometry: geometry) { frame in
                    followItem(preview, frame: frame, geometry: geometry)
                }
        }
    }
    
    private func list(with items: [Item]) -> some View {
        ScrollViewReader { scrollProxy in
            GeometryReader { geometry in
                List {
                    ForEach(items) { item in
                        itemView(for: item, geometry: geometry, scrollProxy: scrollProxy)
                    }
                    .onDelete { offsets in
                        let previewsToRemove = offsets
                            .map { items[$0] }
                            .compactMap { item -> FASubmissionPreview? in
                                guard case let .submissionPreview(preview) = item else { return nil }
                                return preview
                            }
                        model.deleteSubmissionPreviews(previewsToRemove)
                    }
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
                }
                .introspect(.scrollView, on: .iOS(.v16...)) { scrollView in
                    self.scrollView = scrollView
                }
                .trackListFrame()
                .listStyle(.plain)
                // The nav bar chrome (inline title, mode menu, trailing action)
                // is owned by the enclosing SubmissionsTabView so both feed modes
                // can share it. Keeping the title/toolbar above the refresh
                // control there preserves the "toolbar before refresh" ordering.
                // https://stackoverflow.com/a/64700545/869385
                .refreshable {
                    refresh(pulled: true)
                }
                .swap(when: items.isEmpty) {
                    noPreview
                }
                .prefetchingPreviews(model.submissionPreviews, availableWidth: geometry.size.width)
            }
        }
    }
    
    var body: some View {
        Group {
            if let listItems {
                list(with: listItems)
            }
        }
        .overlay(alignment: .top) {
            NotificationOverlay(itemCount: $newSubmissionsCount)
                .offset(y: 40)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            autorefreshIfNeeded()
        }
        // One-shot newer-submissions check after a cold-launch restore, reusing the
        // foreground autorefresh's scroll-preserving choreography. `initial: true`
        // catches the flag whether it's set before or after this view appears.
        .onChange(of: model.shouldCheckForNewerSubmissionsAfterRestore, initial: true) { _, needsCheck in
            guard needsCheck else { return }
            model.shouldCheckForNewerSubmissionsAfterRestore = false
            refresh(pulled: false)
        }
        // Relying on this to know if the view is displayed doesn't always work
        // in the general case, hopefully this view is used in a TabView
        // which calls these modifiers as expected!
        .onAppear {
            currentViewIsDisplayed = true

            // Resume an autorefresh deferred/aborted while the feed was covered
            // (e.g. a notification deep link push). Only set on those paths, so
            // ordinary tab switches don't refresh. Bypass the reachedTop guard:
            // the abort's scrollTo left reachedTop == false, but the resumed
            // scrollTo(.top) re-pins it. See autorefreshIfNeeded's invariant.
            if pendingAutorefresh {
                pendingAutorefresh = false
                autorefreshIfNeeded(ignoreScrollPosition: true)
            }
        }
        .onDisappear {
            currentViewIsDisplayed = false

            // The feed just got covered by a navigation push. If a scroll-managed
            // refresh is in flight, abort it cleanly so no new items are inserted
            // while off-screen (which would lose the restored scroll position),
            // and mark it to re-run once the feed is front-most again.
            if targetScrollItem != nil {
                refreshTask?.cancel()
                refreshTask = nil
                targetScrollItem = nil
                pendingAutorefresh = true
            }
        }
    }
}

// MARK: - Refresh
extension SubmissionsFeedView {
    func refresh(pulled: Bool) {
        Task {
            // The delay gives time for the pull-to-refresh to go back
            // to its position and prevents interrupting animation
            if pulled {
                if let scrollView {
                    while !scrollView.reachedTop {
                        try await Task.sleep(for: .milliseconds(50))
                    }
                } else {
                    try await Task.sleep(for: .seconds(1))
                }
            }
            
            if let item = model.submissionPreviews?.first {
                // This will cause an Item.fetchTrigger to appear in the list,
                // which will effectively cause the refresh
                targetScrollItem = item
            } else {
                // List has no item, so there's no scroll to preserve. Perform
                // a direct fetch
                await storeLocalizedError(in: errorStorage, action: "Submissions Refresh", webBrowserURL: FAURLs.submissionsUrl) {
                    try await fetchSubmissionPreviews()
                }
            }
        }
    }
    
    /// - Parameter ignoreScrollPosition: When `true`, skip the `reachedTop`
    ///   guard (resume path only). Safe because `pendingAutorefresh` is only set
    ///   from a refresh already in flight, which only starts from the top — so
    ///   this can never yank a scrolled-down user.
    func autorefreshIfNeeded(ignoreScrollPosition: Bool = false) {
        guard ignoreScrollPosition || scrollView?.reachedTop ?? true else {
            return
        }

        // If the feed is currently covered (e.g. a notification deep link pushed
        // content over it), don't run the scroll-managed refresh now — it needs
        // the feed on-screen and stable for the full fetch. Defer it; onAppear
        // re-runs this method once the feed is front-most again, where the
        // shouldAutoRefresh check below is re-evaluated.
        guard currentViewIsDisplayed else {
            pendingAutorefresh = true
            return
        }

        if Model.shouldAutoRefresh(with: model.lastSubmissionPreviewsFetchDate) {
            refresh(pulled: false)
        }
    }
    
    /// Whether `error` represents the in-flight refresh being cancelled by
    /// navigation rather than a genuine failure. The underlying URLSession call
    /// surfaces cancellation as `URLError(.cancelled)`, so check that too.
    static func isCancellation(_ error: Error) -> Bool {
        if Task.isCancelled { return true }
        return isCancellationError(error)
    }

    func fetchSubmissionPreviews() async throws {
        let newSubmissionCount = try await model
            .fetchSubmissionPreviews()
        
        withAnimation {
            newSubmissionsCount = newSubmissionCount
        }
    }
}

// MARK: - Previews
#Preview {
    withAsync({ try await Model.demo }) {
        NavigationStack {
            SubmissionsFeedView()
        }
        .environment($0)
        .environment($0.errorStorage)
    }
}

#Preview("Empty feed") {
    withAsync({ try await Model.empty }) {
        NavigationStack {
            SubmissionsFeedView()
        }
        .environment($0)
        .environment($0.errorStorage)
        .preferredColorScheme(.dark)
    }
}

