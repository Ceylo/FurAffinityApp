//
//  ContentView.swift
//  FurAffinity
//
//  Created by Ceylo on 17/10/2021.
//

import SwiftUI
import FAKit

struct HomeView: View {
    @State private var checkingConnection = true
    @State private var session: FASession?
    @State private var showLoginView = false
    
    func updateSession() async {
        checkingConnection = true
        session = await FALoginView.makeSession()
        checkingConnection = false
    }
    
    var center: some View {
        VStack(spacing: 40) {
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
                    Label("Welcome Furry!", systemImage: "pawprint.fill")
                        .font(.title)
                    HStack(spacing: 20) {
                        Button("Login with furaffinity.net") {
                            showLoginView = true
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Link("Register",
                             destination: URL(string: "https://www.furaffinity.net/register")!)
                            .buttonStyle(.bordered)
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
    
    var body: some View {
        VStack {
            Spacer()
            center
            Spacer()
            Link("www.furaffinity.net",
                 destination: URL(string: "https://www.furaffinity.net/")!)
        }
        .padding(.bottom)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
    }
}
