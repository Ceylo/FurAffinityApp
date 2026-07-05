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

    private var loadMoreRow: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        // Drives pagination: appears as the user scrolls to the bottom.
        .onAppear {
            Task { await model.loadMoreSearchResults() }
        }
    }

    private func resultsList(_ results: OrderedSet<FASubmissionPreview>) -> some View {
        GeometryReader { geometry in
            List {
                if model.searchShowingRecentUploads {
                    recentUploadsNotice
                        .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 120))
                        .listRowSeparator(.hidden)
                }
                ForEach(Array(results)) { preview in
                    SubmissionPreviewRow(preview: preview)
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))

                if model.searchCanLoadMore {
                    loadMoreRow
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollDismissesKeyboard(.immediately)
            .refreshable { await model.refreshSearch() }
            .prefetchingPreviews(model.searchResults, availableWidth: geometry.size.width)
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
        .refreshable { await model.refreshSearch() }
    }

    private var contentGroup: some View {
        Group {
            if let results = model.searchResults {
                if results.isEmpty {
                    noResults
                } else {
                    resultsList(results)
                }
            } else if model.searchLoadFailed {
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
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text("Search query not provided. Displaying recent uploads.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            Divider()
        }
    }

    var body: some View {
        contentGroup
        .onAppear {
            // Run the initial search (empty query → recent uploads) only once;
            // the query itself is edited and applied from the Filters sheet.
            if model.searchResults == nil {
                Task { await model.searchSubmissions(model.searchQuery) }
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
