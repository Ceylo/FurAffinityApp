//
//  MediaSaveHandler.swift
//  FurAffinityUI (Android)
//
//  Android counterpart of the iOS `MediaSaveHandler` (Photos / PHPhotoLibrary). Same
//  name, state machine and call sites; the actual MediaStore write arrives in step 4,
//  so callers currently see the button disabled by a nil file URL.
//

import Foundation
import Observation

enum ActionState: Identifiable, CaseIterable {
    case idle
    case inProgress
    case succeeded

    var id: Self { self }
}

@MainActor
@Observable
class MediaSaveHandler {
    var errorStorage: ErrorStorage
    private(set) var state: ActionState = .idle

    init(errorStorage: ErrorStorage) {
        self.errorStorage = errorStorage
    }

    func saveMedia(atFileUrl url: URL) async {
        logger.info("Saving media is not implemented on Android yet (\(url.lastPathComponent))")
    }
}
