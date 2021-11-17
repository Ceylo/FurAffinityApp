//
//  LoggedInView.swift
//  FurAffinity
//
//  Created by Ceylo on 13/11/2021.
//

import SwiftUI
import FAKit

struct LoggedInView: View {
    @Binding var session: FASession?
    @State private var selectedTab: Tab = .submissions

    enum Tab {
        case submissions
        case settings
    }
    
    var body: some View {
        VStack {
            TabView(selection: $selectedTab) {
                if session != nil {
                    SubmissionsFeedView(session: Binding($session)!)
                        .tabItem {
                            Label("Submissions", systemImage: "rectangle.grid.2x2")
                        }
                        .tag(Tab.submissions)
                }
                
                SettingsView(session: $session)
                    .tabItem {
                        Label("Settings", systemImage: "slider.horizontal.3")
                    }
                    .tag(Tab.settings)
            }
        }
    }
}

struct LoggedInView_Previews: PreviewProvider {
    static var previews: some View {
        LoggedInView(session: .constant(OfflineFASession.default))
    }
}
