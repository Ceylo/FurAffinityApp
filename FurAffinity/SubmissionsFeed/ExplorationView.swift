//
//  ExplorationView.swift
//  FurAffinity
//
//  Created by Ceylo on 21/06/2026.
//

import SwiftUI
import FAKit
import Collections

/// The "Explore" mode of the Submissions tab: displays furaffinity.net search
/// results, reusing the watched-feed card layout. The query (free text, tags,
/// and filters) is edited in the Filters sheet; this screen only renders the
/// current results and loads the initial page.
struct ExplorationView: View {
    @Environment(Model.self) private var model

    private func itemView(for preview: FASubmissionPreview) -> some View {
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
        }
    }

    private var loadMoreRow: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        // Drives pagination: appears as the user scrolls to the bottom.
        .onAppear {
            Task { await model.loadMoreExploration() }
        }
    }

    private func resultsList(_ results: OrderedSet<FASubmissionPreview>) -> some View {
        GeometryReader { geometry in
            List {
                if model.explorationShowingRecentUploads {
                    recentUploadsNotice
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                }
                ForEach(Array(results)) { preview in
                    itemView(for: preview)
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))

                if model.explorationCanLoadMore {
                    loadMoreRow
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollDismissesKeyboard(.immediately)
            .refreshable { await model.refreshExploration() }
            .onChange(of: model.explorationResults, initial: true) { _, newValue in
                guard let previews = newValue else { return }
                prefetchThumbnails(for: previews, availableWidth: geometry.size.width)
                prefetchAvatars(for: previews)
            }
        }
    }

    private var noResults: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("No results.")
                    .font(.headline)
                Text("Try a different query or loosen the filters.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
    }

    /// Shown when a search failed with nothing to display, so the user isn't left
    /// staring at a spinner that never resolves. Matches `RemoteView`'s failure
    /// state: a plain message with pull-to-refresh as the retry path. The
    /// underlying error is surfaced separately via the shared error alert.
    private var loadFailed: some View {
        ScrollView {
            Text("Loading failed")
                .foregroundStyle(.secondary)
                .font(.title)
        }
        .defaultScrollAnchor(.center)
        .refreshable { await model.refreshExploration() }
    }

    private var contentGroup: some View {
        Group {
            if let results = model.explorationResults {
                if results.isEmpty {
                    noResults
                } else {
                    resultsList(results)
                }
            } else if model.explorationLoadFailed {
                loadFailed
            } else {
                Centered {
                    ProgressView()
                }
            }
        }
    }

    /// First-row notice when a keyword-less search fell back to recent uploads.
    /// Scrolls away with the results; text stays clear of the floating controls.
    private var recentUploadsNotice: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text("Search query not provided. Displaying recent uploads.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.leading, 16)
            .padding(.trailing, 120) // clears the floating controls
            .padding(.vertical, 10)
            Divider()
        }
    }

    var body: some View {
        contentGroup
        .onAppear {
            // Run the initial search (empty query → recent uploads) only once;
            // the query itself is edited and applied from the Filters sheet.
            if model.explorationResults == nil {
                Task { await model.searchSubmissions(model.explorationQuery) }
            }
        }
    }
}

#Preview {
    withAsync({ try await Model.demo }) {
        NavigationStack {
            ExplorationView()
        }
        .environment($0)
        .environment($0.errorStorage)
    }
}
