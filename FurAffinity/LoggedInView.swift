//
//  LoggedInView.swift
//  FurAffinity
//
//  Created by Ceylo on 13/11/2021.
//

import SwiftUI
import FAKit

struct LoggedInView: View {
    @Binding var session: FASession
    @State private var selectedTab: Tab = .submissions

    enum Tab {
        case submissions
    }
    
    var body: some View {
        VStack {
            TabView(selection: $selectedTab) {
                SubmissionsListView(session: $session)
                    .tabItem {
                        Label("Submissions", systemImage: "rectangle.grid.2x2")
                    }
                    .tag(Tab.submissions)
                
            }
        }
    }
}

struct LoggedInView_Previews: PreviewProvider {
    static var previews: some View {
        LoggedInView(session: .constant(FASession(sampleUsername: "Demo")))
    }
}
