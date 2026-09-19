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

/// The device and app as the privacy policy lists them — model, versions — so
/// nothing an SDK adds ever leaves. Dropped: locale, free memory, low-power mode,
/// and `device_app_hash`, which derives from `identifierForVendor`.
private let listedContextKeys: [String: Set<String>] = [
    "device": ["type", "family", "model", "model_id", "arch", "simulator", "memory_size",
               "storage_size", "processor_count", "cpu_description"],
    "app": ["type", "app_identifier", "app_name", "app_version", "app_build", "app_id",
            "build_type", "app_start_time", "start_type", "in_foreground", "is_active"],
]

private func keepingListedContextOnly(_ context: [String: [String: Any]]?) -> [String: [String: Any]]? {
    context.map { context in
        context.reduce(into: [:]) { kept, entry in
            guard let listed = listedContextKeys[entry.key] else {
                kept[entry.key] = entry.value
                return
            }
            kept[entry.key] = entry.value.filter { listed.contains($0.key) }
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
