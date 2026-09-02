//
//  FAConnectionPool.swift
//  FurAffinityUI (Android)
//
//  The one Swift door to `FAHttpClient`'s connection pool: evict it, guarded by the
//  epoch. Both pipelines come through here — `OkHttpTransport` for pages, wrapped in
//  its own queue hop, and `FAImageStore` for images, from inside the hop it already
//  holds — because there is only one pool to evict and it should be asked for in one
//  voice. The `[CFREPAIR] evicted …` / `evict skipped …` pair is logged here and
//  nowhere else, which is what keeps `summarize-image-log.py` counting one line per
//  repair.
//
//  Unguarded on purpose — an Android substitution file must be, see
//  Android/docs/shared-sources.md § Rules for shared sources. The JNI inside is
//  `canImport(Android)`-guarded and no-ops on Darwin.
//

import Foundation
import FAKit
#if canImport(Android)
import SkipBridge
#endif

enum FAConnectionPool {
    #if canImport(Android)
    /// `nonisolated(unsafe)`: AnyDynamicObject isn't Sendable but wraps a JNI global
    /// ref that is safe to read from any thread.
    nonisolated(unsafe) private static let bridge: AnyDynamicObject? = {
        do {
            return try AnyDynamicObject(className: "fur.affinity.ui.FAHttpBridge")
        } catch {
            logger.error("FAConnectionPool: could not create FAHttpBridge: \(error)")
            return nil
        }
    }()
    #endif

    /// Evict every pooled connection, unless somebody has already done so since
    /// `observed` — `CloudflareConnectionRepair.shouldEvict`, enforced in Kotlin under
    /// a lock. N callers challenged on one generation therefore cause one eviction.
    ///
    /// **Blocking JNI** — call it off the main actor, and off any actor whose executor
    /// you would rather not stall.
    @discardableResult
    static func repair(observed: UInt64) -> FAConnectionRepairResult {
        let unchanged = FAConnectionRepairResult(
            didEvict: false, evictedConnections: 0, epoch: observed
        )
        #if canImport(Android)
        guard let bridge else { return unchanged }
        do {
            let json: String? = try bridge.repair(Int64(observed))
            guard let data = json?.data(using: .utf8),
                  let result = try? JSONDecoder().decode(RepairResult.self, from: data) else {
                logger.error("[CFREPAIR] unreadable evict result \(json ?? "<nil>")")
                return unchanged
            }
            if result.didEvict {
                logger.warning("[CFREPAIR] evicted \(result.evicted) connections, epoch \(observed)→\(result.epoch)")
            } else {
                logger.warning("[CFREPAIR] evict skipped, pool already at epoch \(result.epoch)")
            }
            return FAConnectionRepairResult(
                didEvict: result.didEvict, evictedConnections: result.evicted, epoch: result.epoch
            )
        } catch {
            logger.error("[CFREPAIR] evict threw: \(error)")
            return unchanged
        }
        #else
        return unchanged
        #endif
    }

    private struct RepairResult: Decodable {
        var didEvict: Bool
        var evicted: Int
        var epoch: UInt64
    }
}
