//
//  AppInformation.swift
//  FurAffinity
//
//  Created by Ceylo on 15/01/2023.
//

import Foundation
import Version

struct Release: Decodable {
    let html_url: String
    let draft: Bool
    let prerelease: Bool
    let published_at: String
    let tag_name: String
    let name: String
    let body: String
    
    var version: Version {
        Version(tolerant: tag_name) ?? Version(0,0,0)
    }
}

@MainActor
class AppInformation: ObservableObject {
    let currentVersion = Bundle.main.version
    @Published var latestRelease: Release?
    @Published var isUpToDate: Bool?

    func fetch() {
        Task {
            let url = URL(string: "https://api.github.com/repos/Ceylo/FurAffinityApp/releases/latest")!
            if let data = await URLSession.shared.httpData(from: url, cookies: nil) {
                let release = try JSONDecoder().decode(Release.self, from: data)
                isUpToDate = release.version <= currentVersion
                latestRelease = release
            } else {
                latestRelease = nil
                isUpToDate = nil
            }
        }
    }
}
