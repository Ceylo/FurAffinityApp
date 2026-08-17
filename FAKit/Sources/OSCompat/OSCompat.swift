//
//  OSCompat.swift
//  OSCompat
//
//  Android has no `os` module, so this vends the `Logger`/`OSSignposter` surface
//  shared code uses. Call sites pick between the two with `#if canImport(os)`;
//  this target is only ever a dependency `.when(platforms: [.android])`, so
//  Darwin always resolves the real system module.
//
//  Deliberately *not* named `os` — see the note in FAKit/Package.swift. A module
//  by that name makes `canImport(os)` true across the whole Android build and
//  breaks whichever target happens to compile after it.
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
