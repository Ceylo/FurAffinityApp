//
//  URLMatcher.swift
//  FurAffinity
//
//  Created by Ceylo on 17/03/2023.
//

import Foundation

enum FAURL: Hashable {
    case submission(url: URL)
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
        
        // https://www.furaffinity.net/user/xxx
        // https://www.furaffinity.net/view/nnn/
        let submissionRegex = #//view/\d+/#
//        let userRegex = #//user/.+/#
        
        switch components.path {
        case submissionRegex:
            self = .submission(url: url)
//        case userRegex:
//            self = .user(url: url)
        default:
            return nil
        }
    }
}
