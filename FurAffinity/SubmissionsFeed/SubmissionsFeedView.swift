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

struct SubmissionsFeedView: View {
    @EnvironmentObject var model: Model
    @State private var newSubmissionsCount: Int?
    @Weak private var scrollView: UIScrollView?
    @State private var targetScrollItem: FASubmissionPreview?
    @State private var currentViewIsDisplayed = false
    
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
                
                Task {
                    await fetchSubmissionPreviews()
                    self.targetScrollItem = nil
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
            ZStack(alignment: .leading) {
                NavigationLink(value: FATarget.submission(
                    url: preview.url, previewData: preview
                )) {
                    // Empty navigation link with 0 opacity is a trick to have full width
                    // navigation without a trailing chevron
                    EmptyView()
                }
                .opacity(0)
                
                SubmissionFeedItemView<TitleAuthorHeader>(submission: preview)
                    .id(preview.sid)
                    .onItemFrameChanged(listGeometry: geometry) { frame in
                        followItem(preview, frame: frame, geometry: geometry)
                    }
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
                        model.deleteSubmissionPreviews(atOffsets: offsets)
                    }
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
                }
                .introspect(.scrollView, on: .iOS(.v16...)) { scrollView in
                    self.scrollView = scrollView
                }
                .trackListFrame()
                .listStyle(.plain)
                .overlay(alignment: .topTrailing) {
                    SubmissionsFeedActionView()
                        .padding(.trailing, 20)
                        .padding(.top, 6)
                }
                // Toolbar needs to be setup before refresh control…
                // https://stackoverflow.com/a/64700545/869385
                .navigationTitle("Submissions")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.hidden, for: .navigationBar)
                .refreshable {
                    refresh(pulled: true)
                }
                .swap(when: items.isEmpty) {
                    noPreview
                }
                .onReceive(model.$submissionPreviews.compactMap { $0 }) { previews in
                    let thumbnailsWidth = geometry.size.width - 28.333
                    prefetchThumbnails(for: previews, availableWidth: thumbnailsWidth)
                    prefetchAvatars(for: previews)
                }
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
                await fetchSubmissionPreviews()
            }
        }
    }
    
    func autorefreshIfNeeded() {
        guard scrollView?.reachedTop ?? true else { return }
        guard currentViewIsDisplayed else { return }
        
        if Model.shouldAutoRefresh(with: model.lastSubmissionPreviewsFetchDate) {
            refresh(pulled: false)
        }
    }
    
    func fetchSubmissionPreviews() async {
        let newSubmissionCount = await model
            .fetchSubmissionPreviews()
        
        withAnimation {
            newSubmissionsCount = newSubmissionCount
        }
    }
}

// MARK: - Previews
#Preview {
    NavigationStack {
        SubmissionsFeedView()
    }
    .environmentObject(Model.demo)
}

#Preview("Empty feed") {
    NavigationStack {
        SubmissionsFeedView()
    }
    .environmentObject(Model.empty)
    .preferredColorScheme(.dark)
}
