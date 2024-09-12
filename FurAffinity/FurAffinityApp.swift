//
//  FurAffinityApp.swift
//  FurAffinity
//
//  Created by Ceylo on 17/10/2021.
//

import SwiftUI
import FAKit
import URLImage
import URLImageStore
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
        defaultTracking: .init(sessions: true, appLifecycles: true)
    )
    
    return Amplitude(configuration: config)
}()

@main
struct FurAffinityApp: App {
    @StateObject private var model = Model()
    private var urlImageService = URLImageService(fileStore: URLImageFileStore(), inMemoryStore: URLImageInMemoryStore())
    private var urlImageOptions: URLImageOptions = {
        let fields = URLSessionConfiguration.httpHeadersForFARequests
        return .init(urlRequestConfiguration: .init(allHTTPHeaderFields: fields))
    }()
    
    init() {
        let device = UIDevice.current
        logger.info("Launched FurAffinity \(Bundle.main.version, privacy: .public) on \(device.systemName, privacy: .public) \(device.systemVersion, privacy: .public), \(buildConfiguration, privacy: .public) build")
        logger.debug("Amplitude is \(amplitude == nil ? "left uninitialized" : "initialized")")
    }

    var body: some Scene {
        WindowGroup {
            if model.session == nil {
                HomeView()
                    .environmentObject(model)
                    .transition(.opacity.animation(.default))
            } else {
                LoggedInView()
                    .environmentObject(model)
                    .environment(\.urlImageService, urlImageService)
                    .environment(\.urlImageOptions, urlImageOptions)
                    .transition(.opacity.animation(.default))
            }
        }
    }
}
