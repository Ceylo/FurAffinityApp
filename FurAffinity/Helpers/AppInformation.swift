//
//  AppInformation.swift
//  FurAffinity
//
//  Created by Ceylo on 15/01/2023.
//

import FAKit
import Foundation
import Observation
import Version
#if canImport(FoundationNetworking)
// URLSession/URLRequest live here in corelibs Foundation (Android).
import FoundationNetworking
#endif

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
    /// `Bundle.main` can't answer on Android, so this goes through FAAppVersion — which
    /// can itself come back empty when the bridge is unreachable. Nil rather than a
    /// stand-in: `Version(0, 0, 0)` compares below every release, so the app would badge
    /// "update available" forever and offer the build already running.
    let currentVersion = FAAppVersion.string.flatMap(Version.init(tolerant:))
    var latestRelease: Release?
    var isUpToDate: Bool?

    /// One release feed serves both platforms: the tag carries the IPA and the APK.
    ///
    /// Plain `URLSession` on purpose, on both platforms. FAKit's `httpData(from:cookies:)`
    /// is Darwin-only because Android needs a cookie-replaying, Cloudflare-aware
    /// implementation — none of which api.github.com wants.
    func fetch() async throws {
        let url = URL(string: "https://api.github.com/repos/Ceylo/FurAffinityApp/releases/latest")!
        var request = URLRequest(url: url)
        // GitHub rejects requests without one.
        request.setValue(FAUserAgent.applicationName, forHTTPHeaderField: "User-Agent")

        latestRelease = nil
        isUpToDate = nil

        let data: Data
        do {
            let (body, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                logger.error("Update check: \(url) answered \(response)")
                return
            }
            data = body
        } catch {
            // Silent until now, which made "is the check even running?" unanswerable
            // from a log — the question Android's first release turns on.
            logger.error("Update check: \(url) failed: \(error)")
            return
        }

        let release = try JSONDecoder().decode(Release.self, from: data)
        latestRelease = release
        guard let currentVersion else {
            // `isUpToDate` stays nil, which reads as "up to date" at both consumers.
            logger.error("Update check: latest \(release.version.shortDescription), but the running version is unknown")
            return
        }
        isUpToDate = release.version <= currentVersion
        logger.info("Update check: latest \(release.version.shortDescription), running \(currentVersion.shortDescription)")
    }
}
