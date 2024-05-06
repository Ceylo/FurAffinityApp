//
//  AttributedString+FA.swift
//  
//
//  Created by Ceylo on 11/04/2022.
//

import Foundation
import UIKit

extension AttributedString {
    public init(FAHTML: String) throws {
        let theme = String.FATheme(style: UITraitCollection.current.userInterfaceStyle)
        
        let data = try FAHTML.using(theme: theme).data(using: .utf8).unwrap()
        let nsattrstr = try NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: NSNumber(value: String.Encoding.utf8.rawValue)
            ],
            documentAttributes: nil
        )
        
        self = AttributedString(nsattrstr)
            .transformingAttributes(\.foregroundColor) { foregroundColor in
                if foregroundColor.value == nil {
                    foregroundColor.value = .primary
                }
            }
            .transformingAttributes(\.font) { font in
                font.value = .body
            }
    }
}
