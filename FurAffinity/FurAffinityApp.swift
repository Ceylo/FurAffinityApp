//
//  FurAffinityApp.swift
//  FurAffinity
//
//  Created by Ceylo on 17/10/2021.
//

import SwiftUI
import FAKit
import AmplitudeSwift
import UserNotifications
import Defaults

enum BuildConfiguration: CustomStringConvertible {
    case debug
    case release
    
    var description: String {
        switch self {
        case .debug:
            "debug"
        case .release:
            "release"
        }
    }
}

#if DEBUG
let buildConfiguration = BuildConfiguration.debug
#else
let buildConfiguration = BuildConfiguration.release
#endif

@MainActor
private let amplitude: Amplitude? = {
    guard Secrets.amplitudeApiKey != Secrets.placeholderApiKey else {
        return nil
    }
    
    let trackingOptions = TrackingOptions()
        .disableTrackCity()
        .disableTrackRegion()
        .disableTrackCarrier()
        .disableTrackDMA()
        .disableTrackIpAddress()
        .disableTrackIDFV()
    
    let config = Configuration(
        apiKey: Secrets.amplitudeApiKey,
        trackingOptions: trackingOptions,
        autocapture: [.sessions, .appLifecycles]
    )
    
    return Amplitude(configuration: config)
}()

struct RootView: View {
    @Environment(Model.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var challengeCoordinator = CloudflareChallengeCoordinator.shared

    var body: some View {
        ZStack {
            if model.session == nil {
                HomeView()
            } else {
                LoggedInView()
            }

            // Hidden background WebView: attempts to resolve a CloudFlare
            // challenge passively (no visible sheet). Kept 1×1 and transparent
            // but in the hierarchy so WebKit renders it and runs the challenge
            // JS. Escalates to the sheet if checkbox detection fires or the
            // safety-net timeout expires.
            if challengeCoordinator.backgroundResolutionPending {
                FAChallengeView(
                    onResolved: { CloudflareChallengeCoordinator.shared.markResolved() },
                    onInteractionRequired: { CloudflareChallengeCoordinator.shared.markInteractionRequired() }
                )
                .frame(width: 1, height: 1)
                .opacity(0.001)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .top) {
            if challengeCoordinator.backgroundResolutionPending {
                CloudflareResolutionOverlay()
                    .padding(.top, 8)
                    .transition(.fallAndFade)
            }
        }
        .animation(.default, value: challengeCoordinator.backgroundResolutionPending)
        .transition(.opacity.animation(.default))
        .sheet(
            isPresented: Binding(
                get: { challengeCoordinator.pending },
                set: { isPresented in
                    // markResolved() flips `pending` to false directly; the setter
                    // only fires when SwiftUI wants to dismiss the sheet on its
                    // own (user swipe-down). Treat that as giving up.
                    if !isPresented && challengeCoordinator.pending {
                        challengeCoordinator.markFailed()
                    }
                }
            )
        ) {
            CloudflareChallengeSheet()
        }
        .onChange(of: scenePhase, initial: true) { oldPhase, newPhase in
            logger.info("App scenePhase: \(oldPhase) -> \(newPhase)")
        }
    }
}

@main
struct FurAffinityApp: App {
    @State private var model = Model()

    init() {
        let device = UIDevice.current
        let appState = UIApplication.shared.applicationState
        logger.info("Launched FurAffinity \(Bundle.main.version.shortDescription) on \(device.systemName) \(device.systemVersion), \(buildConfiguration) build [CFDIAG] applicationState=\(appState.rawValue)")
        _ = amplitude
        logger.info("Amplitude is \(amplitude == nil ? "left uninitialized" : "initialized")")
        
        Defaults.runSettingsMigrations()
        BackgroundRefreshManager.register()
        FAImageInliner.dataProvider = kingfisherImageDataProvider
        UNUserNotificationCenter.current().delegate = NotificationCoordinator.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(model.errorStorage)
                .environment(NotificationCoordinator.shared)
        }
    }
}
