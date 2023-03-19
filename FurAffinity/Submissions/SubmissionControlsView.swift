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
    var isFavorite: Bool
    var favoriteAction: () -> Void
    var replyAction: () -> Void
    
    private let buttonsSize: CGFloat = 55
    
    @StateObject private var imageSaveHandler = ImageSaveHandler()
    
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Spacer()

            Button {
                favoriteAction()
            } label: {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
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
                share([submissionUrl])
            } label: {
                Image(systemName: "square.and.arrow.up")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .padding()
            }
            .frame(width: buttonsSize, height: buttonsSize)
            
            Button {
                replyAction()
            } label: {
                Image(systemName: "arrowshape.turn.up.left")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding()
            }
            .frame(width: buttonsSize, height: buttonsSize)
            
            Spacer()
        }
    }
}

struct SubmissionControlsView_Previews: PreviewProvider {
    static var previews: some View {
        SubmissionControlsView(submissionUrl: OfflineFASession.default.submissionPreviews[0].url,
                               fullResolutionImage: UIImage(systemName: "checkmark")?.cgImage,
                               isFavorite: false,
                               favoriteAction: {
            print("I like it")
        }, replyAction: {
            print("Reply")
        })
            .preferredColorScheme(.dark)
    }
}
