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
        
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if self.state != .inProgress {
                self.state = .none
            }
        }
    }
}
