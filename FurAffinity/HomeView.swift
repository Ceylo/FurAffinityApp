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
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.buttonBorderOverlay.opacity(0.5), lineWidth: 0.5)
        }
    }
}

struct HomeView: View {
    @State private var checkingConnection = true
    @EnvironmentObject var model: Model
    @State private var showLoginView = false
    @State private var localSession: OnlineFASession?
    
    func updateSession() async {
        checkingConnection = true
        let session: OnlineFASession?

        if let localSession {
            session = localSession
        } else {
            session = await FALoginView.makeSession()
        }
        
        model.session = session
        checkingConnection = false
    }
    
    var center: some View {
        VStack(spacing: 80) {
            if checkingConnection {
                AppIcon()
                ProgressView("Checking connection…")
            } else {
                if model.session == nil {
                    AppIcon()
                    
                    VStack(spacing: 20) {
                        Button {
                            showLoginView = true
                        } label: {
                            HomeViewButtonContents(text: "Login with furaffinity.net")
                        }
                        
                        Link(destination: FAURLs.signupUrl) {
                            HomeViewButtonContents(text: "Register")
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
                .onChange(of: localSession) { newValue in
                    showLoginView = localSession == nil
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
    HomeView()
        .environmentObject(Model.demo)
}
