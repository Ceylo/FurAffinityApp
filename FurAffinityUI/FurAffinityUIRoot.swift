//
//  FurAffinityUIRoot.swift
//  FurAffinityUI (Android)
//
//  Entry point of the Skip Fuse app. Android-only: this directory is not part of
//  the iOS Xcode target, so nothing here affects the iOS build. Shared iOS
//  sources are pulled in as symlinks under FurAffinityUI/Shared/ as they're
//  ported.
//

import Foundation
import FALogging
import SkipFuse
import SwiftUI

// Superseded by Helpers/Logs.swift once that file joins the Package.swift
// `sources:` allowlist.
let logger = PersistentLogger(subsystem: "net.furaffinity.app", category: "FA")

/// The shared top-level view, loaded from the platform-specific app delegates below.
/* SKIP @bridge */public struct FurAffinityUIRootView: View {
    /* SKIP @bridge */public init() {
    }

    public var body: some View {
        AndroidRootView()
    }
}

/// Global application delegate functions.
/* SKIP @bridge */public final class FurAffinityUIAppDelegate: Sendable {
    /* SKIP @bridge */public static let shared = FurAffinityUIAppDelegate()

    private init() {
    }

    /* SKIP @bridge */public func onInit() {
        logger.debug("onInit")
    }

    /* SKIP @bridge */public func onLaunch() {
        logger.debug("onLaunch")
    }

    /* SKIP @bridge */public func onResume() {
        logger.debug("onResume")
    }

    /* SKIP @bridge */public func onPause() {
        logger.debug("onPause")
    }

    /* SKIP @bridge */public func onStop() {
        logger.debug("onStop")
    }

    /* SKIP @bridge */public func onDestroy() {
        logger.debug("onDestroy")
    }

    /* SKIP @bridge */public func onLowMemory() {
        logger.debug("onLowMemory")
    }
}
