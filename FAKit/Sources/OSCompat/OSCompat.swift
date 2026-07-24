//
//  OSCompat.swift
//  os
//
//  Android has no `os` module. This target is named `os` so shared code can
//  `import os` and use `Logger`/`OSSignposter` unconditionally on both
//  platforms. It is only ever a dependency `.when(platforms: [.android])`,
//  so Darwin always resolves the real system module instead.
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
