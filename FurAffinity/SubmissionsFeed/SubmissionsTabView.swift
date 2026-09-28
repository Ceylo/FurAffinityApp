//
//  SubmissionsTabView.swift
//  FurAffinity
//
//  Created by Ceylo on 21/06/2026.
//

import SwiftUI
import FAKit

/// Hosts the two modes of the first tab — the watched-users feed ("Followed")
/// and search ("Explore"). Rather than a nav bar (which adds height and blurs
/// the feed cards under it), the mode switch and the mode-specific context
/// action float as a pair of round Liquid-Glass buttons over the top-trailing
/// corner of the list. Explore isn't ported to Android, where the tab is the
/// Followed feed and its context action alone.
struct SubmissionsTabView: View {
    // Not private: skipstone can't bridge a private @State/@Environment.
    @Environment(Model.self) var model

    enum Mode: Hashable, CaseIterable {
        case followed
        case explore

        var title: String {
            switch self {
            case .followed: "Followed"
            case .explore: "Explore"
            }
        }

        /// The SF Symbol shown on the mode-switch button for the current mode.
        var symbol: String {
            switch self {
            case .followed: "person.2.fill"
            case .explore: "safari"
            }
        }
    }

    @State var mode: Mode = .followed
    @State var showingFilters = false
    // SkipSwiftUI's `Namespace` is unavailable; `glassEffectUnion` is a pass-through there.
    #if !FA_SKIP_MODULE
    @Namespace var namespace
    #endif

    private var content: some View {
        ZStack {
            // Kept mounted across mode switches (hidden, not torn down) so the
            // Followed feed retains its scroll position when the user dips into
            // Explore and back. Explore stays lazy so it doesn't eagerly search.
            SubmissionsFeedView()
                .opacity(mode == .followed ? 1 : 0)
                .allowsHitTesting(mode == .followed)

            #if !FA_SKIP_MODULE
            if mode == .explore {
                ExplorationView()
            }
            #endif
        }
        // To have the floating controls in top-right from the start.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    #if !FA_SKIP_MODULE
    /// Icon-only mode switch: a glass circle whose icon reflects the current
    /// mode, tapping it opens a picker to switch modes.
    private var modeSwitch: some View {
        Menu {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                }
            }
        } label: {
            ActionControl(systemImage: mode.symbol)
                .opaque()
        }
    }
    #endif

    @ViewBuilder
    private var contextAction: some View {
        switch mode {
        case .followed:
            SubmissionsFeedActionView()
        case .explore:
            #if !FA_SKIP_MODULE
            Button {
                showingFilters = true
            } label: {
                ActionControl(systemImage: "line.3.horizontal.decrease.circle")
                    .opaque()
            }
            #else
            EmptyView()
            #endif
        }
    }

    @ViewBuilder
    private var floatingControls: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer {
                HStack(spacing: 10) {
                    #if !FA_SKIP_MODULE
                    modeSwitch
                        .glassEffect()
                    #endif
                    contextAction
                        .glassEffect()
                }
                #if !FA_SKIP_MODULE
                .glassEffectUnion(id: "floatingControls", namespace: namespace)
                #endif
            }
        } else {
            HStack(spacing: 8) {
                #if !FA_SKIP_MODULE
                modeSwitch
                #endif
                contextAction
            }
        }
    }

    var body: some View {
        content
            .navigationTitle("Submissions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .topTrailing) {
                floatingControls
                    .padding(.trailing, 16)
            }
            #if !FA_SKIP_MODULE
            .sheet(isPresented: $showingFilters) {
                SearchFiltersView(query: model.searchQuery)
            }
            #endif
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
