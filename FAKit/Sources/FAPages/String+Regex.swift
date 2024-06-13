//
//  String+Regex.swift
//  
//
//  Created by Ceylo on 17/10/2021.
//

import Foundation

extension String {
    func substring(matching regex: String) -> String? {
        guard let reg = try? NSRegularExpression(pattern: regex),
              let match = reg.firstMatch(in: self, options: [],
                                         range: NSRange(startIndex..., in: self))
        else { return nil }
        return String(self[Range(match.range(at: 1), in: self)!])
    }
}
