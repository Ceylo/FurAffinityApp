//
//  Text+Markdown.swift
//  FurAffinity
//
//  Created by Ceylo on 25/02/2024.
//

import SwiftUI

extension Text {
    init(markdown: String) {
        #if FA_SKIP_MODULE
        // Android's Foundation has no AttributedString(markdown:); SkipUI renders the key's markdown.
        self.init(LocalizedStringKey(markdown))
        #else
        self.init(try! AttributedString(markdown: markdown))
        #endif
    }
}
