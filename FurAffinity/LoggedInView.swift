//
//  LoggedInView.swift
//  FurAffinity
//
//  Created by Ceylo on 13/11/2021.
//

import SwiftUI
import FAKit
import Combine

struct LoggedInView: View {
    @Environment(Model.self) private var model
    @Environment(NotificationCoordinator.self) private var notificationCoordinator
    @State private var selectedTab: Tab = .submissions
    @State private var navigationStream = PassthroughSubject<FATarget, Never>()
    @State private var submissionsNavigationStack = NavigationPath()
    @State private var notesNavigationStack = NavigationPath()
    @State private var notificationsNavigationStack = NavigationPath()
    @State private var userpageNavigationStack = NavigationPath()

    enum Tab {
        case submissions
        case notes
        case notifications
        case userpage
        case settings
    }
    
    private func append(_ target: FATarget, to tab: Tab) {
        switch tab {
        case .submissions:
            submissionsNavigationStack.append(target)
        case .notes:
            notesNavigationStack.append(target)
        case .notifications:
            notificationsNavigationStack.append(target)
        case .userpage:
            userpageNavigationStack.append(target)
        case .settings:
            fatalError("Internal inconsistency")
        }
    }

    func handleTarget(_ target: FATarget) {
        append(target, to: selectedTab)
    }

    /// Navigates to a target coming from a notification tap. Unlike
    /// `handleTarget`, this works from any tab (including Settings) because
    /// `Tab.forDeepLink(current:)` never yields `.settings`.
    private func navigate(to target: FATarget) {
        let tab = Tab.forDeepLink(current: selectedTab)
        selectedTab = tab
        append(target, to: tab)
    }

    private func drainPendingDeepLink() {
        guard let target = notificationCoordinator.pendingDeepLink else {
            return
        }
        notificationCoordinator.pendingDeepLink = nil
        navigate(to: target)
    }

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                if model.session != nil {
                    NavigationStack(path: $submissionsNavigationStack) {
                        SubmissionsFeedView()
                            .navigationDestination(for: FATarget.self) { nav in
                                view(for: nav)
                            }
                    }
                    .tabItem {
                        Label("Submissions", systemImage: "rectangle.grid.2x2")
                    }
                    .tag(Tab.submissions)
                    
                    NavigationStack(path: $notesNavigationStack) {
                        RemoteNotesView()
                            .navigationDestination(for: FATarget.self) { nav in
                                view(for: nav)
                            }
                    }
                    .badge(model.displayedUnreadNoteCount)
                    .tabItem {
                        Label("Notes", systemImage: "message")
                    }
                    .tag(Tab.notes)
                    
                    NavigationStack(path: $notificationsNavigationStack) {
                        RemoteNotificationsView()
                            .navigationDestination(for: FATarget.self) { nav in
                                view(for: nav)
                            }
                    }
                    .badge(model.displayedNotificationCount)
                    .tabItem {
                        Label("Notifications", systemImage: "bell")
                    }
                    .tag(Tab.notifications)
                    
                    NavigationStack(path: $userpageNavigationStack) {
                        CurrentUserView()
                            .navigationDestination(for: FATarget.self) { nav in
                                view(for: nav)
                            }
                    }
                    .tabItem {
                        Label("Profile", systemImage: "person.crop.circle")
                    }
                    .tag(Tab.userpage)
                }
                
                SettingsView()
                    .badge(model.appInfo.isUpToDate ?? true ? nil : " ")
                    .tabItem {
                        Label("Settings", systemImage: "slider.horizontal.3")
                    }
                    .tag(Tab.settings)
            }
            ErrorDisplay()
        }
        .onOpenURL { url in
            FATarget(with: url).map(handleTarget)
        }
        .environment(\.navigationStream, navigationStream)
        .onReceive(navigationStream) { target in
            handleTarget(target)
        }
        // Drain a notification deep link. `initial: true` covers a tap that
        // cold-launched the app (value already set when this view mounts); the
        // change handler covers taps while the app is already running.
        .onChange(of: notificationCoordinator.pendingDeepLink, initial: true) { _, _ in
            drainPendingDeepLink()
        }
        .onAppear {
            let tabBarAppearance = UITabBarAppearance()
            tabBarAppearance.configureWithDefaultBackground()
            UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
        }
        .backgroundRefreshLifecycle()
    }
}

extension LoggedInView.Tab {
    /// The tab a notification deep link should open in: the currently selected
    /// tab is kept, unless it's `.settings` (which has no navigation stack), in
    /// which case the link opens in `.notifications`. Never returns `.settings`.
    static func forDeepLink(current: LoggedInView.Tab) -> LoggedInView.Tab {
        current == .settings ? .notifications : current
    }
}

#Preview {
    withAsync({ try await Model.demo }) {
        LoggedInView()
            .environment($0)
            .environment($0.errorStorage)
            .environment(NotificationCoordinator.shared)
    }
}
