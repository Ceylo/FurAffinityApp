//
//  ContentView.swift
//  FurAffinity
//
//  Created by Ceylo on 17/10/2021.
//

import SwiftUI
import FAKit

private struct HomeViewButtonContents: View {
    var text: String
    
    var body: some View {
        HStack {
            Spacer()
            Text(text)
                .padding(10)
                .font(.headline)
                .tint(.primary)
            Spacer()
        }
        .background(Color.borderOverlay.opacity(0.5))
        .clipShape(.capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color.buttonBorderOverlay.opacity(0.25), lineWidth: 1)
        }
    }
}

struct HomeView: View {
    @State private var checkingConnection = true
    @EnvironmentObject var model: Model
    @State private var showLoginView = false
    @State private var localSession: OnlineFASession?
    
    func updateSession() async throws {
        checkingConnection = true
        let session: OnlineFASession?

        if let localSession {
            session = localSession
        } else {
            session = await FALoginView.makeSession()
        }
        
        let task = Task.detached(name: "Session init") {
            try await model.setSession(session)
        }
        try await task.value
        checkingConnection = false
    }
    
    var center: some View {
        VStack(spacing: 100) {
            if checkingConnection {
                AppIcon()
                ProgressView("Checking connection…")
            } else {
                if model.session == nil {
                    AppIcon()
                    
                    VStack(spacing: 30) {
                        if #available(iOS 26, *) {
                            Button("Login with furaffinity.net  ") {
                                showLoginView = true
                            }
                            .buttonStyle(.glassProminent)
                            .font(.title2)
                            
                            Link(destination: FAURLs.signupUrl) {
                                Text("Register")
                                    .padding(.horizontal, 5)
                            }
                            .buttonStyle(.glass)
                            .font(.title2)
                        } else {
                            Button {
                                showLoginView = true
                            } label: {
                                HomeViewButtonContents(text: "Login with furaffinity.net")
                            }
                            
                            Link(destination: FAURLs.signupUrl) {
                                HomeViewButtonContents(text: "Register")
                            }
                        }
                    }
                    .padding(.horizontal)
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
            FALoginView(session: $localSession)
                .onChange(of: localSession) { _, newValue in
                    showLoginView = newValue == nil
                }
        }
    }
    
    var body: some View {
        VStack {
            Spacer()
            center
            Spacer()
            HStack {
                Link("furaffinity.app",
                     destination: URL(string: "https://furaffinity.app")!)
                Text("—")
                Link("Privacy Policy",
                     destination: URL(string: "https://github.com/Ceylo/FurAffinityApp/blob/main/Privacy%20Policy.md")!)
            }
        }
        .padding()
    }
}

#Preview {
    withAsync({ try await Model.demo }) {
        HomeView()
            .environmentObject($0)
    }
}
