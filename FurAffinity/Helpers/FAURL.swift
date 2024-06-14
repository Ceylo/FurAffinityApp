//
//  URLMatcher.swift
//  FurAffinity
//
//  Created by Ceylo on 17/03/2023.
//

import Foundation
import FAKit

enum FAURL: Hashable {
    case submission(url: URL, previewData: FASubmissionPreview?)
    case note(url: URL)
    case journal(url: URL)
    case user(url: URL)
    case gallery(url: URL)
    case scraps(url: URL)
    case favorites(url: URL)
}

fileprivate func ~=(regex: Regex<Substring>, str: String) -> Bool {
    (try? regex.firstMatch(in: str)) != nil
}

extension FAURL {
    init?(with url: URL, _ submissionPreviewData: FASubmissionPreview? = nil) {
        guard let url = url.replacingScheme(with: "https"),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.host == "www.furaffinity.net" else {
            return nil
        }
        
        let submissionRegex = #//view/\d+/#     // https://www.furaffinity.net/view/nnn/
        let noteRegex = #//msg/pms/\d+/\d+/#    // https://www.furaffinity.net/msg/pms/n/nnn/#message
        let journalRegex = #//journal/\d+/#     // https://www.furaffinity.net/journal/nnn/
        let userRegex = #//user/.+/#            // https://www.furaffinity.net/user/xxx
        let galleryRegex = #//gallery/.+/#      // https://www.furaffinity.net/gallery/xxx
        let scrapsRegex = #//scraps/.+/#        // https://www.furaffinity.net/scraps/xxx
        let favoritesRegex = #//favorites/.+/#  // https://www.furaffinity.net/favorites/xxx
        
        switch components.path {
        case submissionRegex:
            self = .submission(url: url, previewData: submissionPreviewData)
        case noteRegex:
            self = .note(url: url)
        case journalRegex:
            self = .journal(url: url)
        case userRegex:
            self = .user(url: url)
        case galleryRegex:
            self = .gallery(url: url)
        case scrapsRegex:
            self = .scraps(url: url)
        case favoritesRegex:
            self = .favorites(url: url)
        default:
            return nil
        }
    }
}
