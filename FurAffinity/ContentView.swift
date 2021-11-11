//
//  ContentView.swift
//  FurAffinity
//
//  Created by Ceylo on 17/10/2021.
//

import SwiftUI
import FAKit

struct ContentView: View {
    @State private var checkingConnection = true
    @State private var session: FASession?
    @State private var showLoginView = false
    
    func updateSession() async {
        checkingConnection = true
        session = await FALoginView.makeSession()
        checkingConnection = false
    }
    
    var body: some View {
        VStack(spacing: 20) {
            if checkingConnection {
                ProgressView("Checking connection…")
            } else {
                if let session = session {
                    Text("Connected with user \(session.displayUsername)")
                    Button("Logout") {
                        Task {
                            await FALoginView.logout()
                            await updateSession()
                        }
                    }
                } else {
                    
                    Button("Login") {
                        showLoginView = true
                    }
                }
            }
        }
        .task {
            await updateSession()
        }
        .sheet(isPresented: $showLoginView) {
            Task {
                await updateSession()
            }
        } content: {
            FALoginView(session: $session)
                .onChange(of: session) { newValue in
                    showLoginView = session == nil
                }
        }


    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
