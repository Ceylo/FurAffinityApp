//
//  NoopSignposter.swift
//  FAKit
//
//  Android has no os/Instruments. Mirrors the OSSignposter subset used here so
//  every call site compiles unchanged on both platforms.
//

#if !canImport(os)

struct NoopSignposter {
    struct IntervalState {}

    func beginInterval(_ name: StaticString) -> IntervalState { IntervalState() }
    func endInterval(_ name: StaticString, _ state: IntervalState) {}

    func withIntervalSignpost<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        try body()
    }
}

#endif
