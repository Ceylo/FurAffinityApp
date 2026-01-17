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
    
    func handleTarget(_ target: FATarget) {
        switch selectedTab {
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
                    .badge(model.unreadInboxNoteCount)
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
                    .badge(model.significantNotificationCount)
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
        .onAppear {
            let tabBarAppearance = UITabBarAppearance()
            tabBarAppearance.configureWithDefaultBackground()
            UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
        }
    }
}

#Preview {
    withAsync({ try await Model.demo }) {
        LoggedInView()
            .environment($0)
            .environment($0.errorStorage)
    }
}
