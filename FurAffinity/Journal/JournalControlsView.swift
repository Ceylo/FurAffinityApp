//
//  JournalControlsView.swift
//  FurAffinity
//
//  Created by Ceylo on 27/11/2021.
//

import SwiftUI
import FAKit

struct JournalControlsView: View {
    var journalUrl: URL
    var replyAction: () -> Void
    
    private let buttonsSize: CGFloat = 55
    
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Spacer()
            
            Button {
                share([journalUrl])
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

struct JournalControlsView_Previews: PreviewProvider {
    static var previews: some View {
        JournalControlsView(journalUrl: FAJournal.demo.url,
                            replyAction: {
            print("Reply")
        })
            .preferredColorScheme(.dark)
    }
}
