//
//  LoggedInView.swift
//  FurAffinity
//
//  Created by Ceylo on 13/11/2021.
//

import SwiftUI
import FAKit

struct LoggedInView: View {
    @EnvironmentObject var model: Model
    @State private var selectedTab: Tab = .submissions
    @State private var submissionsNavigationStack = NavigationPath()

    enum Tab {
        case submissions
        case notes
        case settings
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            if model.session != nil {
                NavigationStack(path: $submissionsNavigationStack) {
                    SubmissionsFeedView(navigationStack: $submissionsNavigationStack)
                }
                .tabItem {
                    Label("Submissions", systemImage: "rectangle.grid.2x2")
                }
                .tag(Tab.submissions)
                
                NavigationStack {
                    NotesView()
                }
                .badge(model.unreadNoteCount)
                .tabItem {
                    Label("Notes", systemImage: "message")
                }
                .tag(Tab.notes)
            }
            
            SettingsView()
                .badge(model.appInfo.isUpToDate ?? true ? nil : " ")
                .tabItem {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
                .tag(Tab.settings)
        }
        .onOpenURL { url in
            guard let match = FAURL(with: url) else {
                return
            }
            
            switch selectedTab {
            case .submissions:
                submissionsNavigationStack.append(match)
            case .notes:
                fatalError("Not supported yet")
            case .settings:
                fatalError("Internal inconsistency")
            }
        }
    }
}

struct LoggedInView_Previews: PreviewProvider {
    static var previews: some View {
        LoggedInView()
            .environmentObject(Model.demo)
    }
}
