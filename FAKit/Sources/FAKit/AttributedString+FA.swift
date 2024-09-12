//
//  AttributedString+FA.swift
//  
//
//  Created by Ceylo on 11/04/2022.
//

import Foundation
import UIKit

extension AttributedString {
    @MainActor // needed for NSAttributedString from HTML data which calls WebKit which isn't thread-safe
    public init(FAHTML: String) async throws {
        let token = signposter.beginInterval("AttributedString.init(FAHTML:)")
        defer { signposter.endInterval("AttributedString.init(FAHTML:)", token) }
        let theme = FATheme(style: UITraitCollection.current.userInterfaceStyle)
        
        let data = try await FAHTML
            .using(theme: theme)
            .inliningCSS()
            .data(using: .utf8)
            .unwrap()
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
