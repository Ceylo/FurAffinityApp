//
//  MediaSaveHandler.swift
//  FurAffinity
//
//  Created by Ceylo on 27/11/2021.
//

import SwiftUI
import Photos

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
        await storeLocalizedError(in: errorStorage, action: "Image Save", webBrowserURL: nil) {
            try await PHPhotoLibrary.shared().performChanges { @Sendable in
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, fileURL: url, options: nil)
            }
            
            state = .succeeded
            try? await Task.sleep(for: .seconds(2))
            if state != .inProgress {
                state = .idle
            }
        }
    }
}
