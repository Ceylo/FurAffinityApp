//
//  FAURLs.swift
//  
//
//  Created by Ceylo on 28/10/2023.
//

import Foundation

public enum FAURLs {
    public static let homeUrl = URL(string: "https://www.furaffinity.net")!
    public static let signupUrl = URL(string: "https://www.furaffinity.net/register")!
    
    public static let submissionsUrl = URL(
        string: "https://www.furaffinity.net/msg/submissions/"
    )!
    
    public static let latest72SubmissionsUrl = submissionsUrl.appending(path: "new@72")
    public static func submissionsUrl(from sid: Int) -> URL {
        submissionsUrl.appending(component: "new~\(sid)@72")
    }
    
    public static let notesInboxUrl = URL(
        string: "https://www.furaffinity.net/controls/switchbox/inbox/"
    )!
    
    public static let notificationsUrl = URL(
        string: "https://www.furaffinity.net/msg/others/"
    )!
    
    public static func userpageUrl(for username: String) -> URL? {
        guard !username.isEmpty else {
            return nil
        }
        return try? URL(unsafeString: "https://www.furaffinity.net/user/\(username)/")
    }
    
    public static func avatarUrl(for username: String) -> URL? {
        guard !username.isEmpty else {
            return nil
        }
        
        let str = "https://a.furaffinity.net/\(username).gif"
        return try? URL(unsafeString: str)
    }
    
    public static func usernameFrom(userUrl: URL) -> String? {
        var urlString = userUrl.absoluteString
        if urlString.suffix(1) != "/" {
            urlString.append("/")
        }
        
        guard urlString.wholeMatch(of: /https:\/\/www\.furaffinity\.net\/user\/.+\//) != nil else {
            return nil
        }
        
        return userUrl.lastPathComponent
    }
    
    public static func galleryUrl(for username: String) -> URL {
        URL(string: "https://www.furaffinity.net/gallery/\(username)/")!
    }
    
    public static func scrapsUrl(for username: String) -> URL {
        URL(string: "https://www.furaffinity.net/scraps/\(username)/")!
    }
    
    public static func favoritesUrl(for username: String) -> URL {
        URL(string: "https://www.furaffinity.net/favorites/\(username)/")!
    }
    
    public static func journalsUrl(for username: String) -> URL {
        URL(string: "https://www.furaffinity.net/journals/\(username)/")!
    }
    
    public static func watchlistUrl(for username: String, direction: FAWatchlistPage.WatchDirection) -> URL {
        switch direction {
        case .watchedBy:
            URL(string: "https://www.furaffinity.net/watchlist/to/\(username)/")!
        case .watching:
            URL(string: "https://www.furaffinity.net/watchlist/by/\(username)/")!
        }
    }
    
    public static func parseWatchlistUrl(_ url: URL) -> (username: String, watchDirection: FAWatchlistPage.WatchDirection)? {
        do {
            // https://www.furaffinity.net/watchlist/to/xxx/
            // https://www.furaffinity.net/watchlist/by/xxx/
            let username = try url.absoluteString
                .substring(matching: "\\/watchlist\\/[toby]{2}\\/(.+)\\/")
                .unwrap()
            let direction = try url.absoluteString
                .substring(matching: "\\/watchlist\\/([toby]{2})\\/")
                .unwrap()
            
            let watchDirection: FAWatchlistPage.WatchDirection
            switch direction {
            case "to":
                watchDirection = .watchedBy
            case "by":
                watchDirection = .watching
            default:
                logger.error("\(#file, privacy: .public) - invalid direction in url: \(direction, privacy: .public)")
                return nil
            }
            
            return (username, watchDirection)
        } catch {
            logger.error("\(#file, privacy: .public) - \(error, privacy: .public)")
            return nil
        }
    }
    
    public static func submissionUrl(sid: Int) -> URL {
        URL(string: "https://www.furaffinity.net/view/\(sid)/")!
    }
    
    public static func journalUrl(jid: Int) -> URL {
        URL(string: "https://www.furaffinity.net/journal/\(jid)/")!
    }
}
