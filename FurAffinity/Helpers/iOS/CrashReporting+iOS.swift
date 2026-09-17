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
        options.enableNetworkBreadcrumbs = false
        options.enableCaptureFailedRequests = false
        let since = configuration.reportsSince
        options.beforeSend = { event in
            (event.timestamp ?? .distantFuture) < since ? nil : event
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
