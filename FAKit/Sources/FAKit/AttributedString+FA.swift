//
//  AttributedString+FA.swift
//  
//
//  Created by Ceylo on 11/04/2022.
//

import Foundation
import UIKit

extension AttributedString {
    public init?(FAHTML: String) {
        let theme = String.FATheme(style: UITraitCollection.current.userInterfaceStyle)
        
        guard let data = FAHTML.using(theme: theme).data(using: .utf8),
              let nsattrstr = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: NSNumber(value: String.Encoding.utf8.rawValue)
                ],
                documentAttributes: nil)
        else { return nil }
        
        let attr = AttributedString(nsattrstr)
            .transformingAttributes(\.foregroundColor) { foregroundColor in
                if foregroundColor.value == nil {
                    foregroundColor.value = .primary
                }
            }
            .transformingAttributes(\.font) { font in
                font.value = .body
            }
        
        self.init(NSAttributedString(attr))
    }
}
