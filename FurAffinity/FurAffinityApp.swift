//
//  FurAffinityApp.swift
//  FurAffinity
//
//  Created by Ceylo on 17/10/2021.
//

import SwiftUI
import FAKit
import AmplitudeSwift

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
    @State private var challengeCoordinator = CloudflareChallengeCoordinator.shared

    var body: some View {
        ZStack {
            if model.session == nil {
                HomeView()
            } else {
                LoggedInView()
            }
        }
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
    }
}

@main
struct FurAffinityApp: App {
    @State private var model = Model()

    init() {
        let device = UIDevice.current
        logger.info("Launched FurAffinity \(Bundle.main.version.shortDescription, privacy: .public) on \(device.systemName, privacy: .public) \(device.systemVersion, privacy: .public), \(buildConfiguration, privacy: .public) build")
        _ = amplitude
        logger.info("Amplitude is \(amplitude == nil ? "left uninitialized" : "initialized", privacy: .public)")
        BackgroundRefreshManager.register()
        FAImageInliner.dataProvider = kingfisherImageDataProvider
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(model.errorStorage)
        }
    }
}
