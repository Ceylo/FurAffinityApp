//
//  FALogSubsystem.swift
//  FALogging
//

import Foundation

/// The identifier every logger uses as its subsystem, so that one `adb logcat -s` or
/// Console filter catches all of them.
///
/// `Bundle.main.bundleIdentifier` is nil in a plain SwiftPM module on Android
/// (corelibs Foundation, no bundle behind it), and in the Skip Fuse module it answers
/// the *module's* package name rather than the installed applicationId — which carries
/// a per-worktree suffix on a debug build. So the app layer installs `override` from
/// the platform's package manager at startup, before anything logs.
public enum FALogSubsystem {
    /// Set once at startup where `Bundle.main` can't answer. `nonisolated(unsafe)`:
    /// written once before any concurrency starts, read everywhere after.
    nonisolated(unsafe) public static var override: String?

    /// What a process with neither answer logs under: the Android test runner and the
    /// Darwin bridge, neither of which installs an override. One shared string rather
    /// than a per-module invention, so nothing has to guess which one to filter on.
    public static let fallback = "FurAffinity"

    public static var identifier: String {
        override ?? Bundle.main.bundleIdentifier ?? fallback
    }
}
