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

@main
struct FurAffinityApp: App {
    @StateObject private var model = Model()
    private var urlImageService = URLImageService(fileStore: URLImageFileStore(), inMemoryStore: URLImageInMemoryStore())
    private var urlImageOptions: URLImageOptions = {
        let fields = URLSessionConfiguration.httpHeadersForFARequests
        return .init(urlRequestConfiguration: .init(allHTTPHeaderFields: fields))
    }()

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
