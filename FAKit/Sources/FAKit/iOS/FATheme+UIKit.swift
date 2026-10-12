//
//  FATheme+UIKit.swift
//  FAKit
//
//  Created by Ceylo on 10/09/2024.
//


#if !os(Android)

import UIKit

extension FATheme {
    init(style: UIUserInterfaceStyle) {
        switch style {
        case .unspecified, .dark:
            self = .dark
        case .light:
            self = .light
        @unknown default: // Also the website default when not logged in
            self = .dark
        }
    }
}

#endif
