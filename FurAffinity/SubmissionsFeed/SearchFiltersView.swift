//
//  SearchFiltersView.swift
//  FurAffinity
//
//  Created by Ceylo on 21/06/2026.
//

import SwiftUI
import FAKit

/// Sheet editing the Explore search filters. Applies by running a fresh search
/// (which also persists the criteria). Gender filtering is intentionally absent
/// in v1 — its URL param encoding still needs verifying against a real search.
struct SearchFiltersView: View {
    @Environment(Model.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query: FASearchQuery

    init(query: FASearchQuery) {
        _query = State(initialValue: query)
    }

    private func ratingBinding(_ rating: Rating) -> Binding<Bool> {
        Binding(
            get: { query.ratings.contains(rating) },
            set: { query.ratings.formSymmetricToggle(rating, on: $0) }
        )
    }

    private func contentTypeBinding(_ type: FASearchQuery.ContentType) -> Binding<Bool> {
        Binding(
            get: { query.contentTypes.contains(type) },
            set: { query.contentTypes.formSymmetricToggle(type, on: $0) }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Sort") {
                    Picker("Order", selection: $query.sortOrder) {
                        Text("Relevancy").tag(FASearchQuery.SortOrder.relevancy)
                        Text("Date").tag(FASearchQuery.SortOrder.date)
                        Text("Popularity").tag(FASearchQuery.SortOrder.popularity)
                    }
                    Picker("Direction", selection: $query.sortDirection) {
                        Text("Descending").tag(FASearchQuery.SortDirection.descending)
                        Text("Ascending").tag(FASearchQuery.SortDirection.ascending)
                    }
                }

                Section("Date range") {
                    Picker("Within", selection: $query.dateRange) {
                        ForEach(FASearchQuery.DateRange.allCases, id: \.self) { range in
                            Text(range.displayName).tag(range)
                        }
                    }
                }

                Section("Match words") {
                    Picker("Match", selection: $query.matchMode) {
                        Text("All").tag(FASearchQuery.MatchMode.all)
                        Text("Any").tag(FASearchQuery.MatchMode.any)
                        Text("Extended").tag(FASearchQuery.MatchMode.extended)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle("General", isOn: ratingBinding(.general))
                    Toggle("Mature", isOn: ratingBinding(.mature))
                    Toggle("Adult", isOn: ratingBinding(.adult))
                } header: {
                    Text("Rating")
                } footer: {
                    Text("Mature and adult results only appear if your FurAffinity account allows them.")
                }

                Section("Content type") {
                    Toggle("Art", isOn: contentTypeBinding(.art))
                    Toggle("Music", isOn: contentTypeBinding(.music))
                    Toggle("Flash", isOn: contentTypeBinding(.flash))
                    Toggle("Story", isOn: contentTypeBinding(.story))
                    Toggle("Photo", isOn: contentTypeBinding(.photo))
                    Toggle("Poetry", isOn: contentTypeBinding(.poetry))
                }

                Section {
                    Button("Reset to defaults") {
                        query = .default
                    }
                }
            }
            .navigationTitle("Search Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        Task { await model.searchSubmissions(query) }
                        dismiss()
                    }
                }
            }
        }
    }
}

private extension Set {
    /// Inserts or removes `element` to match `on`.
    mutating func formSymmetricToggle(_ element: Element, on: Bool) {
        if on { insert(element) } else { remove(element) }
    }
}

extension FASearchQuery.DateRange {
    var displayName: String {
        switch self {
        case .oneDay: "Past day"
        case .threeDays: "Past 3 days"
        case .sevenDays: "Past week"
        case .thirtyDays: "Past 30 days"
        case .ninetyDays: "Past 90 days"
        case .oneYear: "Past year"
        case .threeYears: "Past 3 years"
        case .fiveYears: "Past 5 years"
        case .all: "All time"
        }
    }
}

#Preview {
    withAsync({ try await Model.demo }) {
        SearchFiltersView(query: .default)
            .environment($0)
            .environment($0.errorStorage)
    }
}
