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
// SwiftUI, not Observation: it is what pulls in SkipAndroidBridge's shadowed
// ObservationRegistrar. See AppInformation.swift.
import SwiftUI

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
        let saved = await MediaBridge.saveImage(atFileUrl: url)
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
