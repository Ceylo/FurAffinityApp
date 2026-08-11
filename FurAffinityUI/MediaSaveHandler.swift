//
//  MediaSaveHandler.swift
//  FurAffinityUI (Android)
//
//  Android counterpart of the iOS `MediaSaveHandler` (Photos / PHPhotoLibrary): same
//  name, same `ActionState` machine driving `SaveButton`'s checkmark, but writing to
//  MediaStore through `FAMediaBridge`.
//

import Foundation
import Dispatch
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
        state = .inProgress
        let saved = await MediaBridge.saveImageOffMain(atFileUrl: url)
        guard saved else {
            state = .idle
            storeError(
                MediaSaveError.saveFailed,
                in: errorStorage,
                action: "Image Save",
                webBrowserURL: nil
            )
            return
        }

        state = .succeeded
        try? await Task.sleep(for: .seconds(2))
        if state != .inProgress {
            state = .idle
        }
    }
}

enum MediaSaveError: LocalizedError {
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .saveFailed: "The image could not be written to your gallery."
        }
    }
}

extension MediaBridge {
    /// `saveImage` blocks on JNI I/O, and FurAffinityUI is a native Skip module, so it
    /// must not run on a cooperative-pool thread. Hop to a real queue.
    static func saveImageOffMain(atFileUrl url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: saveImage(atFileUrl: url))
            }
        }
    }

    static func shareOffMain(fileUrl url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: share(fileUrl: url))
            }
        }
    }
}
