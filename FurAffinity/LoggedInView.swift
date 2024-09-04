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
    @EnvironmentObject var model: Model
    @State private var selectedTab: Tab = .submissions
    @State private var navigationStream = PassthroughSubject<FAURL, Never>()
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
    
    func handleURL(_ url: FAURL) {
        switch selectedTab {
        case .submissions:
            submissionsNavigationStack.append(url)
        case .notes:
            notesNavigationStack.append(url)
        case .notifications:
            notificationsNavigationStack.append(url)
        case .userpage:
            userpageNavigationStack.append(url)
        case .settings:
            fatalError("Internal inconsistency")
        }
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            if model.session != nil {
                NavigationStack(path: $submissionsNavigationStack) {
                    SubmissionsFeedView()
                        .navigationDestination(for: FAURL.self) { nav in
                            view(for: nav)
                        }
                }
                .tabItem {
                    Label("Submissions", systemImage: "rectangle.grid.2x2")
                }
                .tag(Tab.submissions)
                
                NavigationStack(path: $notesNavigationStack) {
                    NotesView()
                        .navigationDestination(for: FAURL.self) { nav in
                            view(for: nav)
                        }
                }
                .badge(model.unreadNoteCount)
                .tabItem {
                    Label("Notes", systemImage: "message")
                }
                .tag(Tab.notes)
                
                NavigationStack(path: $notificationsNavigationStack) {
                    RemoteNotificationsView()
                        .navigationDestination(for: FAURL.self) { nav in
                            view(for: nav)
                        }
                }
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }
                .tag(Tab.notifications)
                
                NavigationStack(path: $userpageNavigationStack) {
                    CurentUserView()
                        .navigationDestination(for: FAURL.self) { nav in
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
        .onOpenURL { url in
            FAURL(with: url).map(handleURL)
        }
        .environment(\.navigationStream, navigationStream)
        .onReceive(navigationStream, perform: { url in
            handleURL(url)
        })
        .onAppear {
            let tabBarAppearance = UITabBarAppearance()
            tabBarAppearance.configureWithDefaultBackground()
            UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
        }
    }
}

struct LoggedInView_Previews: PreviewProvider {
    static var previews: some View {
        LoggedInView()
            .environmentObject(Model.demo)
    }
}
