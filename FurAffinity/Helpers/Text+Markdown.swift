//
//  Text+Markdown.swift
//  FurAffinity
//
//  Created by Ceylo on 25/02/2024.
//

import SwiftUI

extension Text {
    init(markdown: String) {
        self.init(try! AttributedString(markdown: markdown))
    }
}
