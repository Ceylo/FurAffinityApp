//
//  AppInformation.swift
//  FurAffinity
//
//  Created by Ceylo on 15/01/2023.
//

import FAKit
import Foundation
// Not `import Observation`: on Android the @Observable macro expands to
// `Observation.ObservationRegistrar`, and only SwiftUI's re-exported
// SkipAndroidBridge shadows that name with the registrar Compose actually
// tracks. Importing the real module instead leaves this object silently inert.
import SwiftUI
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
    /// Nil when the marketing version is not semver-parseable. A stand-in would be
    /// worse than nothing: `Version(0, 0, 0)` compares below every release, so the app
    /// would badge "update available" forever and offer the build already running.
    let currentVersion = Version(tolerant: FAAppVersion.string)
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

        let data: Data
        do {
            let (body, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                logger.error("Update check: \(url) answered \(response)")
                latestRelease = nil
                isUpToDate = nil
                return
            }
            data = body
        } catch {
            // Silent until now, which made "is the check even running?" unanswerable
            // from a log — the question Android's first release turns on.
            logger.error("Update check: \(url) failed: \(error)")
            latestRelease = nil
            isUpToDate = nil
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
