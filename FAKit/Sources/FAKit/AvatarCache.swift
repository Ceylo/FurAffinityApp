//
//  AvatarCache.swift
//  FAKit
//
//  Created by Ceylo on 04/09/2024.
//

import Foundation
import Cache

public protocol AvatarCacheDelegate: AnyObject {
    /// Implement this to try to provide the avatar url when the cache could not
    /// provide it.
    func avatarUrlCacheMiss(for username: String) async -> URL?
}

public actor AvatarCache {
    private weak var delegate: AvatarCacheDelegate?
    
    public init(delegate: AvatarCacheDelegate) {
        self.delegate = delegate
    }
    
    private var avatarUrlTasks = [String: Task<URL?, Swift.Error>]()
    private let avatarUrlsCache: Storage<String, URL> = try! .init(
        diskConfig: DiskConfig(name: "AvatarURLs"),
        memoryConfig: MemoryConfig(),
        transformer: TransformerFactory.forCodable(ofType: URL.self)
    )
    private var lastFlushDate = Date.distantPast
    
    func avatarUrl(for username: String) async -> URL? {
        guard !username.isEmpty else {
            return nil
        }
        
        let previousTask = avatarUrlTasks[username]
        let delegate = self.delegate
        let newTask = Task { () -> URL? in
            _ = await previousTask?.result
            if -lastFlushDate.timeIntervalSinceNow > 60 {
                try avatarUrlsCache.removeExpiredObjects()
                lastFlushDate = Date()
            }
            
            if let url = try? avatarUrlsCache.object(forKey: username) {
                return url
            }
            
            if previousTask != nil {
                // Previous task for the same user has failed, no need to try again now
                return nil
            }
            
            guard let avatarUrl = await delegate?.avatarUrlCacheMiss(for: username)
            else { return nil }
            
            try cacheAvatarUrl(avatarUrl, for: username)
            return avatarUrl
        }
        
        avatarUrlTasks[username] = newTask
        
        return try? await newTask.result.get()
    }
    
    func cacheAvatarUrl(_ url: URL, for username: String) throws {
        guard !avatarUrlsCache.objectExists(forKey: username) else {
            return
        }
        
        let validDays = (7..<14).randomElement()!
        let expiry = Expiry.days(validDays)
        try avatarUrlsCache.setObject(url, forKey: username, expiry: expiry)
        logger.info("Cached url \(url, privacy: .public) for user \(username, privacy: .public) for \(validDays) days")
    }
    
    public func cachedAvatarUrl(for username: String) -> URL? {
        try? avatarUrlsCache.object(forKey: username)
    }
}

private extension Expiry {
    static func days(_ days: Int) -> Expiry {
        .seconds(TimeInterval(60 * 60 * 24 * days))
    }
}
