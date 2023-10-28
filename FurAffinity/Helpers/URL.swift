//
//  URL.swift
//  FurAffinity
//
//  Created by Ceylo on 28/10/2023.
//

import Foundation

extension URL {
    var schemelessDisplayString: String {
        var displayString = self.absoluteString
        if let scheme {
            displayString = displayString.replacingOccurrences(of: scheme + ":", with: "")
        }
        return displayString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
