//
//  LoggedInView.swift
//  FurAffinity
//
//  Created by Ceylo on 13/11/2021.
//

import SwiftUI

struct LoggedInView: View {
    @State private var selectedTab: Tab = .submissions

    enum Tab {
        case submissions
    }
    
    var body: some View {
        VStack {
            TabView(selection: $selectedTab) {
                SubmissionsListView()
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
        LoggedInView()
    }
}
