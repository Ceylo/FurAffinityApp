//
//  FATheme.swift
//  FAKit
//
//  Created by Ceylo on 10/09/2024.
//


import UIKit

enum FATheme: CustomStringConvertible {
    case light
    case dark
    
    var description: String {
        switch self {
        case .light:
            "light"
        case .dark:
            "dark"
        }
    }
}


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
