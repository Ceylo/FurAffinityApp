//
//  ExplorationView.swift
//  FurAffinity
//
//  Created by Ceylo on 21/06/2026.
//

import SwiftUI
import FAKit
import Collections

/// The "Explore" mode of the Submissions tab: a furaffinity.net search with a
/// query field and filters, reusing the watched-feed card layout for results.
struct ExplorationView: View {
    @Environment(Model.self) private var model
    @State private var searchText = ""
    @State private var includedTags: [String] = []
    @State private var excludedTags: [String] = []
    @State private var debounceTask: Task<Void, Never>?
    @FocusState private var searchFieldFocused: Bool

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

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search everywhere", text: $searchText)
                .submitLabel(.search)
                .focused($searchFieldFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit {
                    debounceTask?.cancel()
                    runSearch()
                    searchFieldFocused = false
                }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(.quaternary))
        .padding(.horizontal)
        .padding(.vertical, 8)
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
            searchBar
            TagSearchEditor(includedTags: $includedTags, excludedTags: $excludedTags)
            if model.explorationShowingRecentUploads {
                recentUploadsLabel
            }
            contentGroup
        }
        .onChange(of: searchText) { _, _ in
            debounceTask?.cancel()
            debounceTask = Task {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                runSearch()
            }
        }
        .onChange(of: includedTags) { _, _ in
            debounceTask?.cancel()
            runSearch()
        }
        .onChange(of: excludedTags) { _, _ in
            debounceTask?.cancel()
            runSearch()
        }
        .onAppear {
            // Seed the inputs from the remembered query and run the initial search
            // (empty query → recent uploads) only once.
            searchText = model.explorationQuery.text
            includedTags = model.explorationQuery.includedTags
            excludedTags = model.explorationQuery.excludedTags
            if model.explorationResults == nil {
                Task { await model.searchSubmissions(model.explorationQuery) }
            }
        }
    }

    /// Runs a new search built from the current text + tag inputs. Skipping a
    /// query equal to the remembered one avoids re-searching on the programmatic
    /// seed in `onAppear` and other no-op changes.
    private func runSearch() {
        var query = model.explorationQuery
        query.text = searchText
        query.includedTags = includedTags
        query.excludedTags = excludedTags
        guard query != model.explorationQuery else { return }
        Task { await model.searchSubmissions(query) }
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
