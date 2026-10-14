//
//  PendingNotificationRecord.swift
//  FurAffinity
//
//  Created by Ceylo on 24/07/2026.
//

import Foundation
import Defaults

/// Everything needed to rebuild and post one notification without re-parsing FA
/// pages. Persisted (via `Defaults[.pendingNotificationQueue]`) at a checkpoint
/// before the slow media+post phase, so a background run expired mid-flight resumes
/// the remainder next time instead of redoing or losing it.
///
/// Lives apart from `BackgroundRefreshManager` so the Defaults key that stores it can
/// be shared with the Android build without dragging in BackgroundTasks/Kingfisher.
struct PendingNotificationRecord: Codable, Defaults.Serializable, Equatable {
    /// Stable per-item key (e.g. `"submission-123"`, `"shout-456"`) — prevents the
    /// same item being enqueued twice across discovery passes.
    let dedupKey: String
    /// Notification header (the author's display name).
    let title: String
    /// Final message body, with any type emoji prefix already applied.
    let body: String
    /// Author handle, used to download the avatar at post time.
    let author: String
    /// Deep-link URL string carried in `userInfo`.
    let url: String
    /// Resolved best 400px thumbnail URL (submissions only; nil otherwise).
    let thumbnailURLString: String?
    /// Whether the thumbnail attachment must be blurred (rating != .general).
    let needsBlur: Bool
}
