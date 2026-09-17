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
        // Crashes and hangs only: no identifiers, no captured UI, no tracing.
        options.sendDefaultPii = false
        options.attachScreenshot = false
        options.attachViewHierarchy = false
        options.enableAppHangTracking = true
        options.tracesSampleRate = nil
        options.enableAutoPerformanceTracing = false
        options.enableNetworkBreadcrumbs = false
        options.enableCaptureFailedRequests = false
    }
}

func stopPlatformCrashReporter() {
    SentrySDK.close()
}

#endif
