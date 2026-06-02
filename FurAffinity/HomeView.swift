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
    @Environment(Model.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(ErrorStorage.self) private var errorStorage
    @State private var showLoginView = false
    @State private var localSession: OnlineFASession?
    @State private var didTryAutologin = false
    @State private var loginErrorStorage = ErrorStorage()
    
    func updateSession() async throws {
        checkingConnection = true
        defer {
            checkingConnection = false
        }
        let session: OnlineFASession?

        if let localSession {
            session = localSession
        } else {
            session = try await FALoginView.makeSession()
        }
        
        let task = Task.detached(name: "Session init") {
            try await model.setSession(session)
        }
        try await task.value
    }
    
    var center: some View {
        ZStack {
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
            ErrorDisplay()
        }
        .task {
            logger.info("[CFDIAG] HomeView autologin .task fired; scenePhase=\(String(describing: scenePhase), privacy: .public), applicationState=\(UIApplication.shared.applicationState.rawValue, privacy: .public), didTryAutologin=\(didTryAutologin, privacy: .public)")
            guard !didTryAutologin else {
                logger.info("[CFDIAG] HomeView autologin SKIPPED by didTryAutologin guard (leftover state, no fresh attempt)")
                return
            }
            didTryAutologin = true
            logger.info("[CFDIAG] HomeView autologin PROCEEDING; updateSession() start")
            await storeLocalizedError(in: errorStorage, action: "Auto-login", webBrowserURL: nil) {
                do {
                    try await updateSession()
                    logger.info("[CFDIAG] HomeView autologin updateSession() succeeded")
                } catch {
                    logger.error("[CFDIAG] HomeView autologin updateSession() failed: \(type(of: error), privacy: .public) — \(String(describing: error), privacy: .public)")
                    throw error
                }
            }
        }
        .sheet(
            isPresented: $showLoginView,
            onDismiss: {
                if loginErrorStorage.error != nil {
                    errorStorage.error = loginErrorStorage.error
                }
                loginErrorStorage.error = nil
                
                guard errorStorage.error == nil else {
                    return
                }
                
                Task {
                    await storeLocalizedError(in: errorStorage, action: "Login", webBrowserURL: nil) {
                        try await updateSession()
                    }
                }
            },
            content: {
                FALoginView(session: $localSession, onError: {
                    storeError($0, in: loginErrorStorage, action: "Login", webBrowserURL: nil)
                    showLoginView = false
                })
                .onChange(of: localSession) { _, newValue in
                    showLoginView = newValue == nil
                }
            })
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
            .environment($0)
            .environment($0.errorStorage)
    }
}
