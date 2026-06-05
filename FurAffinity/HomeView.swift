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
            await autologinIfActive()
        }
        .onChange(of: scenePhase) {
            Task { await autologinIfActive() }
        }
        // Deterministic logged-out behavior: once autologin has concluded
        // without a session, discard any deep link from a notification tap so
        // it can't replay after a later manual login. Gating on
        // !checkingConnection avoids racing the cold-launch autologin window.
        .onChange(of: checkingConnection) { _, checking in
            if !checking && model.session == nil {
                NotificationCoordinator.shared.pendingDeepLink = nil
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
    
    /// Runs autologin once, but only while the app is foregrounded.
    ///
    /// On a `BGAppRefreshTask` launch SwiftUI builds the scene and fires `.task`
    /// with `scenePhase == .background`; logging in there would push failures
    /// (e.g. an unsolvable Cloudflare challenge) into `ErrorStorage` and surface a
    /// stale "Auto-login failed" alert at the next foreground. The
    /// `.onChange(of: scenePhase)` trigger resumes the deferred attempt.
    func autologinIfActive() async {
        logger.info("[CFDIAG] HomeView autologin trigger; scenePhase=\(String(describing: scenePhase)), applicationState=\(UIApplication.shared.applicationState.rawValue), didTryAutologin=\(didTryAutologin)")
        guard scenePhase == .active else {
            logger.info("[CFDIAG] HomeView autologin DEFERRED; app not active (scenePhase=\(String(describing: scenePhase)))")
            return
        }
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
                logger.error("[CFDIAG] HomeView autologin updateSession() failed: \(type(of: error)) — \(String(describing: error))")
                throw error
            }
        }
    }
}

#Preview {
    withAsync({ try await Model.demo }) {
        HomeView()
            .environment($0)
            .environment($0.errorStorage)
    }
}
