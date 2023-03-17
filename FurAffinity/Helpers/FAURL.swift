//
//  URLMatcher.swift
//  FurAffinity
//
//  Created by Ceylo on 17/03/2023.
//

import Foundation

enum FAURL: Hashable {
    case submission(url: URL)
    case note(url: URL)
//    case user(url: URL)
}

fileprivate func ~=(regex: Regex<Substring>, str: String) -> Bool {
    (try? regex.firstMatch(in: str)) != nil
}

extension FAURL {
    init?(with url: URL) {
        guard let url = url.replacingScheme(with: "https"),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.host == "www.furaffinity.net" else {
            return nil
        }
        
        // https://www.furaffinity.net/view/nnn/
        // https://www.furaffinity.net/msg/pms/n/nnn/#message
        // https://www.furaffinity.net/user/xxx
        let submissionRegex = #//view/\d+/#
        let noteRegex = #//msg/pms/\d+/\d+/#
//        let userRegex = #//user/.+/#
        
        switch components.path {
        case submissionRegex:
            self = .submission(url: url)
        case noteRegex:
            self = .note(url: url)
//        case userRegex:
//            self = .user(url: url)
        default:
            return nil
        }
    }
}
