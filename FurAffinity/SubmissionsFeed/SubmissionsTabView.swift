//
//  SubmissionsTabView.swift
//  FurAffinity
//
//  Created by Ceylo on 21/06/2026.
//

import SwiftUI
import FAKit

/// Hosts the two modes of the first tab — the watched-users feed ("Following")
/// and search ("Explore") — and owns the shared nav-bar chrome: a title dropdown
/// menu to switch modes plus the mode-specific trailing action.
struct SubmissionsTabView: View {
    @Environment(Model.self) private var model

    enum Mode: Hashable {
        case following
        case explore

        var title: String {
            switch self {
            case .following: "Following"
            case .explore: "Explore"
            }
        }
    }

    @State private var mode: Mode = .following
    @State private var showingFilters = false

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .following:
            SubmissionsFeedView()
        case .explore:
            ExplorationView()
        }
    }

    private var titleMenu: some View {
        Menu {
            Picker("Mode", selection: $mode) {
                Label("Following", systemImage: "heart").tag(Mode.following)
                Label("Explore", systemImage: "safari").tag(Mode.explore)
            }
        } label: {
            HStack(spacing: 4) {
                Text(mode.title)
                    .font(.headline)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private var trailingAction: some View {
        switch mode {
        case .following:
            SubmissionsFeedActionView()
        case .explore:
            Button {
                showingFilters = true
            } label: {
                Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
            }
        }
    }

    var body: some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    titleMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    trailingAction
                }
            }
            .sheet(isPresented: $showingFilters) {
                SearchFiltersView(query: model.explorationQuery)
            }
    }
}

#Preview {
    withAsync({ try await Model.demo }) {
        NavigationStack {
            SubmissionsTabView()
        }
        .environment($0)
        .environment($0.errorStorage)
    }
}
