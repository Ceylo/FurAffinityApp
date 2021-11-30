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

    enum Tab {
        case submissions
        case settings
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            if model.session != nil {
                SubmissionsFeedView()
                    .tabItem {
                        Label("Submissions", systemImage: "rectangle.grid.2x2")
                    }
                    .tag(Tab.submissions)
            }
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
                .tag(Tab.settings)
        }
    }
}

struct LoggedInView_Previews: PreviewProvider {
    static var previews: some View {
        LoggedInView()
            .environmentObject(Model.demo)
    }
}
