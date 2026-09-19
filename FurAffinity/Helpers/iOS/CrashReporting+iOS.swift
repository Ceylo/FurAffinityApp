//
//  CrashReporting+iOS.swift
//  FurAffinity
//

#if !FA_SKIP_MODULE

import Foundation
import Sentry

func startPlatformCrashReporter(_ configuration: CrashReportingConfiguration) {
    SentrySDK.start { options in
        options.dsn = configuration.dsn
        options.releaseName = configuration.release
        options.environment = configuration.environment
        // The app's own frameworks, beside the executable Sentry counts by default.
        for module in ["FAKit", "FAPages", "FALogging"] {
            options.add(inAppInclude: module)
        }
        // Crashes and hangs only: no identifiers, no captured UI, no tracing.
        options.sendDefaultPii = false
        options.attachScreenshot = false
        options.attachViewHierarchy = false
        options.enableAppHangTracking = true
        options.tracesSampleRate = nil
        options.enableAutoPerformanceTracing = false
        options.enableCaptureFailedRequests = false
        // Nothing sent without a crash, and nothing in a report but the crash: no
        // session per launch, no breadcrumbs (UI, lifecycle, system, network).
        options.enableAutoSessionTracking = false
        options.enableAutoBreadcrumbTracking = false
        options.enableNetworkBreadcrumbs = false
        options.maxBreadcrumbs = 0
        let since = configuration.reportsSince
        options.beforeSend = { event in
            guard (event.timestamp ?? .distantFuture) >= since else { return nil }
            event.context = keepingListedContextOnly(event.context)
            return event
        }
    }
}

/// The contexts the privacy policy covers, so nothing an SDK adds ever leaves:
/// `trace` (random ids) whole, the OS, device and app cut to the fields it lists.
/// Dropped among others: `culture`, which non-fatal events (a hang) carry with
/// the timezone and locale; the device's locale, free memory and low-power mode;
/// `device_app_hash`, derived from `identifierForVendor`; the jailbreak check.
private let wholeContexts: Set<String> = ["trace"]
private let listedContextKeys: [String: Set<String>] = [
    "os": ["type", "name", "version", "build", "kernel_version"],
    "device": ["type", "family", "model", "model_id", "arch", "simulator", "memory_size",
               "storage_size", "processor_count", "cpu_description"],
    "app": ["type", "app_identifier", "app_name", "app_version", "app_build", "app_id",
            "build_type", "app_start_time", "start_type", "in_foreground", "is_active"],
]

private func keepingListedContextOnly(_ context: [String: [String: Any]]?) -> [String: [String: Any]]? {
    context.map { context in
        context.reduce(into: [:]) { kept, entry in
            if wholeContexts.contains(entry.key) {
                kept[entry.key] = entry.value
            } else if let listed = listedContextKeys[entry.key] {
                kept[entry.key] = entry.value.filter { listed.contains($0.key) }
            }
        }
    }
}

func stopPlatformCrashReporter() {
    SentrySDK.close()
}

func setPlatformCrashReporterTag(_ key: String, _ value: String) {
    SentrySDK.configureScope { $0.setTag(value: value, key: key) }
}

func crashPlatformReporterInKotlin() {
    logger.error("Crash test kotlinException is Android only")
}

#endif
