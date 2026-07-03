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

    private var contentGroup: some View {
        Group {
            if let results = model.explorationResults {
                if results.isEmpty {
                    noResults
                } else {
                    resultsList(results)
                }
            } else {
                Centered {
                    ProgressView()
                }
            }
        }
    }

    /// Shown when a keyword-less search fell back to FA's recent uploads, so the
    /// results aren't mistaken for matches of a forgotten query.
    private var recentUploadsLabel: some View {
        Text("Recent uploads")
            .font(.subheadline)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.bottom, 8)
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.explorationShowingRecentUploads {
                recentUploadsLabel
            }
            contentGroup
        }
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
