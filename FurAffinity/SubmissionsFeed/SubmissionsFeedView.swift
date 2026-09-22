//
//  SubmissionsFeedView.swift
//  FurAffinity
//
//  Created by Ceylo on 13/11/2021.
//

import SwiftUI
import FAKit
import Defaults
import OrderedCollections
#if canImport(UIKit)
import UIKit
#endif
// SwiftUIIntrospect isn't a dependency of the Skip module, and `@Weak` is its
// `@_spi(Advanced)` wrapper. `FA_SKIP_MODULE` rather than `os(Android)`: the module's
// Darwin bridge compile doesn't have the package either.
#if !FA_SKIP_MODULE
@_spi(Advanced) import SwiftUIIntrospect
#endif

// Not private: skipstone can't bridge a private @State/@Environment. Non-state
// members below stay private.
struct SubmissionsFeedView: View {
    @Environment(Model.self) var model
    @Environment(ErrorStorage.self) var errorStorage
    @State var newSubmissionsCount: Int?
    @State var targetScrollItem: FASubmissionPreview?
    @State var currentViewIsDisplayed = false
    @State var refreshTask: Task<Void, Never>?
    @State var pendingAutorefresh = false
    /// Whether the first row's top edge is still visible. Only tracked and read on
    /// Skip, which has no scroll view to ask. See `trackFirstItemTop`.
    @State var firstItemIsAtTop = true
    #if !FA_SKIP_MODULE
    @Weak var scrollView: UIScrollView?
    #endif
    
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
    
    private var listItems: [FASubmissionPreview]? {
        model.submissionPreviews.map { Array($0) }
    }

    /// This implements the most reliable way known to be able to update the list
    /// with new items at the beginning, while preventing the list from scrolling away
    /// of `targetScrollItem`.
    ///
    /// Mounted as a zero-size overlay on the target row rather than as a list row of
    /// its own: SkipUI floors every row at 32 dp, so a row here left a visible gap at
    /// the top of the feed and, being the first visible item, took over Compose's
    /// scroll anchor — only to be destroyed in the very turn the new rows land.
    private func fetchTriggerView(with targetPreview: FASubmissionPreview, scrollProxy: ScrollViewProxy) -> some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                scrollProxy.scrollTo(targetPreview.id, anchor: .top)

                refreshTask = Task {
                    do {
                        try await fetchSubmissionPreviews()
                        self.targetScrollItem = nil
                        self.refreshTask = nil
                    } catch {
                        // Ours: the feed got covered by a navigation push.
                        // `onDisappear` owns the cleanup and re-arms through
                        // `pendingAutorefresh`, so leave the choreography
                        // untouched for the return.
                        if Task.isCancelled { return }
                        // Not ours — the feed is still on screen. Clear the arming,
                        // or every later refresh waits on one that never finishes.
                        if !isCancellationError(error) {
                            storeError(error, in: errorStorage, action: "Submissions Refresh", webBrowserURL: FAURLs.submissionsUrl)
                        }
                        self.targetScrollItem = nil
                        self.refreshTask = nil
                    }
                }
            }
            .onDisappear {
                scrollProxy.scrollTo(targetPreview.id, anchor: .top)
                Defaults[.lastViewedSubmissionID] = targetPreview.sid
            }
    }
    
    private func followItem(_ preview: FASubmissionPreview, frame: CGRect?, geometry: GeometryProxy) {
        guard let frame else { return }
        let listFrame = geometry.frame(in: .global)
        // A zero-height frame would make both ratios NaN, and `ClosedRange` traps on those.
        guard listFrame.height > 0 else { return }
        let itemTop = frame.minY / listFrame.height
        let itemBottom = frame.maxY / listFrame.height
        let isActive = (itemTop...itemBottom).contains(0.3)
        if isActive {
            Defaults[.lastViewedSubmissionID] = preview.sid
        }
    }
    
    /// Skip's stand-in for the scroll position, from the frame reports `followItem`
    /// already receives. The first row's `minY` is the 10 pt `listRowInsets` gap at
    /// rest and goes negative once its top is under the list; the report turns nil when
    /// the row leaves the list and stops once it is recycled, so the last value must
    /// stay meaningful. Hence "at top" is `minY > 0`, with 10 pt of harmless slack.
    /// Only Skip reads it; on iOS the write would invalidate the feed on every scroll
    /// tick for nothing.
    ///
    /// The first row is resolved live rather than captured per row: a refresh moves
    /// rows without rebuilding them, so a captured flag can end up on the wrong one.
    private func trackFirstItemTop(_ preview: FASubmissionPreview, frame: CGRect?) {
        #if FA_SKIP_MODULE
        guard preview.id == model.submissionPreviews?.first?.id else { return }
        // A nil frame means the row left the list, which is decidedly not "at top".
        let isAtTop = (frame?.minY ?? -1) > 0
        // Only on change: this runs for every scroll frame the first row is visible.
        if isAtTop != firstItemIsAtTop {
            firstItemIsAtTop = isAtTop
        }
        #endif
    }

    private func itemView(for preview: FASubmissionPreview, geometry: GeometryProxy, scrollProxy: ScrollViewProxy) -> some View {
        SubmissionPreviewRow(preview: preview)
            .onItemFrameChanged(listGeometry: geometry) { frame in
                followItem(preview, frame: frame, geometry: geometry)
                trackFirstItemTop(preview, frame: frame)
            }
            .overlay {
                if preview == targetScrollItem {
                    fetchTriggerView(with: preview, scrollProxy: scrollProxy)
                }
            }
    }

    private func list(with items: [FASubmissionPreview]) -> some View {
        ScrollViewReader { scrollProxy in
            GeometryReader { geometry in
                List {
                    ForEach(items) { preview in
                        itemView(for: preview, geometry: geometry, scrollProxy: scrollProxy)
                    }
                    .onDelete { offsets in
                        model.deleteSubmissionPreviews(offsets.map { items[$0] })
                    }
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
                }
                .applying { list in
                    #if FA_SKIP_MODULE
                    list
                    #else
                    list.introspect(.scrollView, on: .iOS(.v16...)) { scrollView in
                        self.scrollView = scrollView
                    }
                    #endif
                }
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
                .prefetchingPreviews(model.submissionPreviews, availableWidth: geometry.faSize.width)
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
                // 35, not 40: the badge now carries 5pt of transparent shadow inset.
                .offset(y: 35)
        }
        .autorefreshingOnForeground {
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
    /// Waits for the pull-to-refresh control to retract, so inserting items doesn't
    /// interrupt its animation.
    func waitForPullToSettle() async throws {
        #if FA_SKIP_MODULE
        // Compose retracts its own indicator and there is no scroll view to observe.
        // Deliberately not a blind sleep: a dead second before the fetch would be
        // worse than today's Android behavior.
        #else
        if let scrollView {
            while !scrollView.reachedTop {
                try await Task.sleep(for: .milliseconds(50))
            }
        } else {
            try await Task.sleep(for: .seconds(1))
        }
        #endif
    }

    /// Whether the feed is scrolled to the top. Skip has no scroll view to ask, so it
    /// goes by whether the first row's top edge is still visible (`trackFirstItemTop`).
    var scrollViewIsAtTop: Bool {
        #if FA_SKIP_MODULE
        firstItemIsAtTop
        #else
        scrollView?.reachedTop ?? true
        #endif
    }

    func refresh(pulled: Bool) {
        Task {
            // The delay gives time for the pull-to-refresh to go back
            // to its position and prevents interrupting animation
            if pulled {
                try await waitForPullToSettle()
            }

            // A refresh is already armed. Wait for it rather than starting a second
            // fetch or throwing away its scroll choreography.
            if targetScrollItem != nil {
                if await waitForArmedRefresh() { return }
                // It never completed: its trigger row never composed, so there is no
                // scroll left to preserve. Drop it and fetch directly — a missed
                // geometry report must not be able to wedge the feed.
                refreshTask?.cancel()
                refreshTask = nil
                targetScrollItem = nil
                await fetchDirectly()
                return
            }

            if let item = model.submissionPreviews?.first {
                // Setting the target mounts the fetch trigger on that row, which is
                // what actually starts the refresh.
                refreshTask = nil
                targetScrollItem = item
            } else {
                // Nothing on screen to hold in place, so no choreography to run.
                await fetchDirectly()
            }
        }
    }

    /// Waits for an armed refresh to finish, by polling the arming its trigger clears
    /// rather than the task: `refreshTask` is set by the trigger's `onAppear`, so it is
    /// still nil in the window between arming and SwiftUI rendering.
    ///
    /// - Returns: `false` if the arming outlived the wait — nothing is coming.
    private func waitForArmedRefresh(attempts: Int = 100) async -> Bool {
        for _ in 0..<attempts {
            if targetScrollItem == nil { return true }
            // Cancellation means teardown, not a stale arming.
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return true }
        }
        return targetScrollItem == nil
    }

    private func fetchDirectly() async {
        await storeLocalizedError(in: errorStorage, action: "Submissions Refresh", webBrowserURL: FAURLs.submissionsUrl) {
            try await fetchSubmissionPreviews()
        }
    }
    
    /// - Parameter ignoreScrollPosition: When `true`, skip the `reachedTop`
    ///   guard (resume path only). Safe because `pendingAutorefresh` is only set
    ///   from a refresh already in flight, which only starts from the top — so
    ///   this can never yank a scrolled-down user.
    func autorefreshIfNeeded(ignoreScrollPosition: Bool = false) {
        guard ignoreScrollPosition || scrollViewIsAtTop else {
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
    
    func fetchSubmissionPreviews() async throws {
        let newSubmissionCount = try await model
            .fetchSubmissionPreviews()
        
        // Not `withAnimation`: it marks the whole Compose frame on SkipUI.
        newSubmissionsCount = newSubmissionCount
    }
}

// MARK: - Previews
#if !FA_SKIP_MODULE
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
#endif

