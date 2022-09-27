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
    @EnvironmentObject var model: Model
    @State private var showLoginView = false
    @State private var localSession: FASession?
    
    func updateSession() async {
        checkingConnection = true
        let session: FASession?

        if let localSession {
            session = localSession
        } else {
            session = await FALoginView.makeSession()
        }
        
        model.session = session
        checkingConnection = false
    }
    
    var center: some View {
        VStack(spacing: 40) {
            if checkingConnection {
                ProgressView("Checking connection…")
            } else {
                if model.session == nil {
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
            Link("www.furaffinity.net",
                 destination: URL(string: "https://www.furaffinity.net/")!)
        }
        .padding(.bottom)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
            .environmentObject(Model.demo)
    }
}
