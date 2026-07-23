//
//  UserPreviewData.swift
//  FurAffinity
//
//  Created by Ceylo on 24/07/2026.
//

import Foundation

/// Split out of `UserPreviewView` so `FATarget` can carry it without the user UI.
struct UserPreviewData: Hashable {
    var username: String
    var displayName: String?
    var avatarUrl: URL?
}
