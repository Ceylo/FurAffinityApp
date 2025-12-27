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
    private let draft: Bool
    private let prerelease: Bool
    private let published_at: String
    private let tag_name: String
    let name: String
    let body: String
    
    var version: Version {
        Version(tolerant: tag_name) ?? Version(0,0,0)
    }
}

extension Version {
    var shortDescription: String {
        if patch != 0 {
            "\(major).\(minor).\(patch)"
        } else {
            "\(major).\(minor)"
        }
    }
}

@MainActor
@Observable
class AppInformation {
    let currentVersion = Bundle.main.version
    var latestRelease: Release?
    var isUpToDate: Bool?

    func fetch() async throws {
        let url = URL(string: "https://api.github.com/repos/Ceylo/FurAffinityApp/releases/latest")!
        if let data = try? await URLSession.shared.httpData(from: url, cookies: nil) {
            let release = try JSONDecoder().decode(Release.self, from: data)
            isUpToDate = release.version <= currentVersion
            latestRelease = release
        } else {
            latestRelease = nil
            isUpToDate = nil
        }
    }
}
