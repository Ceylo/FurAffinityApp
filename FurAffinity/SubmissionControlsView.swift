//
//  SubmissionControlsView.swift
//  FurAffinity
//
//  Created by Ceylo on 27/11/2021.
//

import SwiftUI

struct SubmissionControlsView: View {
    var submissionUrl: URL
    var fullResolutionImage: CGImage?
    var likeAction: (() -> Void)?
    
    private let buttonsSize: CGFloat = 55
    
    @StateObject private var imageSaveHandler = ImageSaveHandler()
    
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Spacer()
            Link(destination: submissionUrl) {
                Image(systemName: "safari")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding()
            }
            .frame(width: buttonsSize, height: buttonsSize)
            
            SaveButton(state: imageSaveHandler.state) {
                imageSaveHandler.startSaving(fullResolutionImage!)
            }
            .frame(width: buttonsSize, height: buttonsSize)
            .disabled(fullResolutionImage == nil)
            
            Button {
                likeAction?()
            } label: {
                Image(systemName: "heart")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding()
            }
            .frame(width: buttonsSize, height: buttonsSize)
            .disabled(likeAction == nil)
            
            Spacer()
        }
    }
}

struct SubmissionControlsView_Previews: PreviewProvider {
    static var previews: some View {
        SubmissionControlsView(submissionUrl: OfflineFASession.default.submissionPreviews[0].url,
                               fullResolutionImage: UIImage(systemName: "checkmark")?.cgImage)
            .preferredColorScheme(.dark)
    }
}
