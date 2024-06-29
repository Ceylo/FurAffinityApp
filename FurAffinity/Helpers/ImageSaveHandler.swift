//
//  ImageSaveHandler.swift
//  FurAffinity
//
//  Created by Ceylo on 27/11/2021.
//

import SwiftUI

enum ActionState: Identifiable, CaseIterable {
    case none
    case inProgress
    case succeeded
    case failed
    
    var id: Self { self }
}

@MainActor
class ImageSaveHandler: NSObject, ObservableObject {
    @Published var state: ActionState = .none
    
    func startSaving(_ image: CGImage) {
        let image = UIImage(cgImage: image)
        UIImageWriteToSavedPhotosAlbum(
            image, self,
            #selector(ImageSaveHandler.image(_:didFinishSavingWithError:contextInfo:)),
            nil)
        state = .inProgress
    }
    
    @objc func image(_ image: UIImage, didFinishSavingWithError error: NSError?, contextInfo: UnsafeRawPointer)  {
        state = error == nil ? .succeeded : .failed
        
        Task { [weak self] in
            try await Task.sleep(for: .seconds(2))
            guard let self = self else { return }
            if self.state != .inProgress {
                self.state = .none
            }
        }
    }
}
