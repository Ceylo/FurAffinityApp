//
//  String+Regex.swift
//  
//
//  Created by Ceylo on 17/10/2021.
//

import Foundation

extension String {
    func substring(matching regex: String, captureIndex: Int = 1) -> String? {
        guard let reg = try? NSRegularExpression(pattern: regex),
              let match = reg.firstMatch(in: self, options: [],
                                         range: NSRange(startIndex..., in: self))
        else { return nil }
        return String(self[Range(match.range(at: captureIndex), in: self)!])
    }
}
