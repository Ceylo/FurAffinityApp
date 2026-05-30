//
//  HTTPCookie+Logging.swift
//  FAKit
//
//  Created by Ceylo on 29/05/2026.
//

import Foundation

extension HTTPCookie {
    var loggingDescription: String {
        "[\(self.name)=\(self.value.prefix(8))…, domain=\(self.domain), path=\(self.path)]"
    }
}

extension Collection where Element == HTTPCookie {
    var loggingDescription: String {
        map(\.loggingDescription).joined(separator: ", ")
    }
}
