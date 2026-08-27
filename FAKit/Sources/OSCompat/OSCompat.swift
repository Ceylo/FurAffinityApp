//
//  OSCompat.swift
//  OSCompat
//
//  Android has no `os` module, so this vends the `Logger`/`OSSignposter` surface
//  shared code uses. Call sites pick between the two with `#if canImport(os)`;
//  this target is only ever a dependency `.when(platforms: [.android])`, so
//  Darwin always resolves the real system module.
//
//  It must NOT be named `os`. A module by that name lands in the shared Modules
//  directory and makes `canImport(os)` true for *every* target in the Android build,
//  so whichever target compiles after it takes its Apple branch and fails — Defaults
//  on `AndroidNDK`, swift-android-native's AndroidLogging on `OSLog`, its
//  AndroidSystem on `os_unfair_lock`. Which target breaks is a scheduling race:
//  intermittent in debug, and a hard block in release.
//

#if os(Android)

// Logger over __android_log_write, tagged "<subsystem>/<category>".
@_exported import AndroidLogging

/// No-op signposter: Android has no Instruments backend. Mirrors the
/// `OSSignposter` subset used by FAKit/FAPages so call sites compile unchanged.
public struct OSSignposter: Sendable {
    public struct IntervalState: Sendable {}

    public init(logger: Logger) {}
    public init(subsystem: String, category: String) {}

    public func beginInterval(_ name: StaticString) -> IntervalState { IntervalState() }
    public func beginInterval(_ name: StaticString, _ message: String) -> IntervalState { IntervalState() }
    public func endInterval(_ name: StaticString, _ state: IntervalState) {}

    public func withIntervalSignpost<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        try body()
    }
}

#endif
