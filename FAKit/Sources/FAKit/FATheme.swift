//
//  FATheme.swift
//  FAKit
//
//  Created by Ceylo on 10/09/2024.
//

import Foundation
#if !os(Android)
import UIKit
#endif

public enum FATheme: CustomStringConvertible, Sendable {
    case light
    case dark
    
    public var description: String {
        switch self {
        case .light:
            "light"
        case .dark:
            "dark"
        }
    }
}

extension FATheme {
    /// The app's current theme where `UITraitCollection` doesn't exist: the Android
    /// app installs it at launch, before anything reads it — hence no isolation, like
    /// `FAWebViewUserAgent.platformProvider`. Nil means dark, the website default.
    nonisolated(unsafe) public static var currentProvider: (@Sendable () -> FATheme)?

    @MainActor static var current: FATheme {
        #if os(Android)
        currentProvider?() ?? .dark
        #else
        FATheme(style: UITraitCollection.current.userInterfaceStyle)
        #endif
    }
}
