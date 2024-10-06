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
    case failed
    
    var id: Self { self }
}

@MainActor
class MediaSaveHandler: NSObject, ObservableObject {
    @Published var state: ActionState = .idle
    
    func saveMedia(atFileUrl url: URL) async {
        state = .inProgress
        do {
            try await PHPhotoLibrary.shared().performChanges { @Sendable in
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, fileURL: url, options: nil)
            }
            
            state = .succeeded
            try await Task.sleep(for: .seconds(2))
            if state != .inProgress {
                state = .idle
            }
        } catch {
            logger.error("\(error, privacy: .public)")
            self.state = .failed
        }
    }
}
