//
//  SubmissionsTabView.swift
//  FurAffinity
//
//  Created by Ceylo on 21/06/2026.
//

import SwiftUI
import FAKit

/// Hosts the two modes of the first tab — the watched-users feed ("Following")
/// and search ("Explore"). Rather than a nav bar (which adds height and blurs
/// the feed cards under it), the mode switch and the mode-specific context
/// action float as a pair of round Liquid-Glass buttons over the top-trailing
/// corner of the list.
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

        /// The SF Symbol shown on the mode-switch button for the current mode.
        var symbol: String {
            switch self {
            case .following: "heart"
            case .explore: "safari"
            }
        }
    }

    @State private var mode: Mode = .following
    @State private var showingFilters = false
    @Namespace var namespace

    private var content: some View {
        ZStack {
            // Kept mounted across mode switches (hidden, not torn down) so the
            // Following feed retains its scroll position when the user dips into
            // Explore and back. Explore stays lazy so it doesn't eagerly search.
            SubmissionsFeedView()
                .opacity(mode == .following ? 1 : 0)
                .allowsHitTesting(mode == .following)

            if mode == .explore {
                ExplorationView()
            }
        }
        // To have the floating controls in top-right from the start.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Icon-only mode switch: a glass circle whose icon reflects the current
    /// mode, tapping it opens a picker to switch modes.
    private var modeSwitch: some View {
        Menu {
            Picker("Mode", selection: $mode) {
                Label("Following", systemImage: "heart").tag(Mode.following)
                Label("Explore", systemImage: "safari").tag(Mode.explore)
            }
        } label: {
            ActionControl(systemImage: mode.symbol)
                .opaque()
        }
    }

    @ViewBuilder
    private var contextAction: some View {
        switch mode {
        case .following:
            SubmissionsFeedActionView()
        case .explore:
            Button {
                showingFilters = true
            } label: {
                ActionControl(systemImage: "line.3.horizontal.decrease")
                    .opaque()
            }
        }
    }

    @ViewBuilder
    private var floatingControls: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer {
                HStack(spacing: 10) {
                    modeSwitch
                        .glassEffect()
                    contextAction
                        .glassEffect()
                }
                .glassEffectUnion(id: "floatingControls", namespace: namespace)
            }
        } else {
            HStack(spacing: 8) {
                modeSwitch
                contextAction
            }
        }
    }

    var body: some View {
        content
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .topTrailing) {
                floatingControls
                    .padding(.trailing, 16)
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
