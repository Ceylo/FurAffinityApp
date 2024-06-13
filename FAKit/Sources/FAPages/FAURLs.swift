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
    
    public static func galleryUrl(for username: String) -> URL {
        URL(string: "https://www.furaffinity.net/gallery/\(username)/")!
    }
    
    public static func scrapsUrl(for username: String) -> URL {
        URL(string: "https://www.furaffinity.net/scraps/\(username)/")!
    }
    
    public static func favoritesUrl(for username: String) -> URL {
        URL(string: "https://www.furaffinity.net/favorites/\(username)/")!
    }
    
    public static func submissionUrl(sid: Int) -> URL {
        URL(string: "https://www.furaffinity.net/view/\(sid)/")!
    }
}
