//
//  FurAffinityApp.swift
//  FurAffinity
//
//  Created by Ceylo on 17/10/2021.
//

import SwiftUI
import FAKit

@main
struct FurAffinityApp: App {
    @State private var session: FASession?
    
    var body: some Scene {
        WindowGroup {
            if session == nil {
                HomeView(session: $session)
            } else {
                Text("Submissions")
                    .transition(.opacity.animation(.easeInOut))
            }
        }
    }
}
