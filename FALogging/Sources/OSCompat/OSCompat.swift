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

import CAndroidTrace

/// Signposter over ATrace, so intervals show up as slices in a Perfetto trace.
/// Mirrors the `OSSignposter` subset used by FAKit/FAPages so call sites compile
/// unchanged.
///
/// ATrace sections are a per-thread stack, so an interval must begin and end on the
/// same thread: never let one span an `await`. An end on another thread is dropped
/// rather than popping someone else's section. When no trace is recording, the cost
/// is one `ATrace_isEnabled()` check.
public struct OSSignposter: Sendable {
    public struct IntervalState: Sendable {
        fileprivate let threadID: pid_t?
    }

    /// The kernel truncates trace markers; cut on a UTF-8 boundary ourselves.
    private static let maxSectionNameBytes = 127

    public init(logger: Logger) {}
    public init(subsystem: String, category: String) {}

    public func beginInterval(_ name: StaticString) -> IntervalState {
        begin { name.description }
    }

    public func beginInterval(_ name: StaticString, _ message: String) -> IntervalState {
        begin { "\(name): \(message)" }
    }

    public func endInterval(_ name: StaticString, _ state: IntervalState) {
        guard let threadID = state.threadID, threadID == gettid() else { return }
        ATrace_endSection()
    }

    public func withIntervalSignpost<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        let state = beginInterval(name)
        defer { endInterval(name, state) }
        return try body()
    }

    private func begin(_ sectionName: () -> String) -> IntervalState {
        guard ATrace_isEnabled() else { return IntervalState(threadID: nil) }
        var utf8: [UInt8] = []
        for scalar in sectionName().unicodeScalars {
            let bytes = UTF8.encode(scalar)!
            guard utf8.count + bytes.count <= Self.maxSectionNameBytes else { break }
            utf8.append(contentsOf: bytes)
        }
        utf8.append(0)
        utf8.withUnsafeBufferPointer { buffer in
            buffer.withMemoryRebound(to: CChar.self) { ATrace_beginSection($0.baseAddress) }
        }
        return IntervalState(threadID: gettid())
    }
}

#endif
