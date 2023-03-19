//
//  String+FA.swift
//  
//
//  Created by Ceylo on 11/04/2022.
//

import Foundation
import UIKit

extension String {
    private var fixingLinks: String {
        self.replacingOccurrences(of: "href=\"/", with: "href=\"https://www.furaffinity.net/")
            .replacingOccurrences(of: "src=\"//", with: "src=\"https://")
            .replacingOccurrences(of: "src=\"/", with: "src=\"https://www.furaffinity.net/")
    }
    
    public var selfContainedFAHtmlSubmission: String {
        let htmlPrefix = """
        <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
        <html lang="en" class="no-js" xmlns="http://www.w3.org/1999/xhtml">
        <head>
            <meta charset="utf-8" />
            <meta name="viewport" content="width=device-width, initial-scale=1.0" />
            <link type="text/css" rel="stylesheet" href="/themes/beta/css/ui_theme_dark.css" />
        </head>
        <body data-static-path="/themes/beta">
            <div class="section-body">
                <div class="submission-description user-submitted-links">
        """
        let htmlSuffix = "</div></div></body></html>"
        return (htmlPrefix + self + htmlSuffix)
            .fixingLinks
    }
    
    public var selfContainedFAHtmlComment: String {
        """
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html lang="en" class="no-js" xmlns="http://www.w3.org/1999/xhtml">
    <head>
        <meta charset="utf-8" />
        <link type="text/css" rel="stylesheet" href="https://www.furaffinity.net/themes/beta/css/ui_theme_dark.css" />
    </head>
    <body>\(self)</body>
</html>
""".fixingLinks
    }
    
    public var selfContainedFAHtmlUserDescription: String { selfContainedFAHtmlComment }

    enum FATheme {
        case light
        case dark
    }
    
    func using(theme: FATheme) -> String {
        if theme == .light {
            return replacingOccurrences(of: "ui_theme_dark.css", with: "ui_theme_light.css")
        } else {
            return self
        }
    }
}

extension String.FATheme {
    init(style: UIUserInterfaceStyle) {
        switch style {
        case .unspecified, .dark:
            self = .dark
        case .light:
            self = .light
        @unknown default:
            self = .dark
        }
    }
}
