//
//  FAAppVersion.swift
//  FAKit
//

import Foundation

/// The app's marketing version — `CFBundleShortVersionString` on Apple platforms,
/// `versionName` on Android.
///
/// It reaches FA in the User-Agent and drives the update check, so both platforms
/// have to answer with the same string. `Bundle.main.infoDictionary` is *empty* in a
/// Skip Fuse native module (corelibs Foundation, no Info.plist), so the app layer
/// installs `override` from the platform's package manager at startup, before
/// anything reads it. An app with no version at all is broken beyond anything a
/// caller can do about it, so `string` traps rather than handing everyone an Optional.
public enum FAAppVersion {
    /// Set once at startup where `Bundle.main` can't answer. `nonisolated(unsafe)`:
    /// written once before any concurrency starts, read everywhere after.
    nonisolated(unsafe) public static var override: String?

    public static var string: String {
        (override ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)!
    }

    /// Set once at startup on Android, like `override`.
    nonisolated(unsafe) public static var commitOverride: String?

    /// The short git hash the app was built from (`FACommit` on Apple platforms,
    /// `BuildConfig.GIT_COMMIT` on Android), or nil when the build couldn't read it.
    public static var commit: String? {
        let commit = (commitOverride ?? Bundle.main.infoDictionary?["FACommit"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return commit?.isEmpty == false ? commit : nil
    }
}
