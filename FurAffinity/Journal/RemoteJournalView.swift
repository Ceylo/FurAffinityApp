//
//  RemoteJournalView.swift
//  FurAffinity
//
//  Created by Ceylo on 19/03/2023.
//

import SwiftUI
import FAKit
import URLImage

struct RemoteJournalView: View {
    var url: URL
    @EnvironmentObject var model: Model
    
    var body: some View {
        RemoteView(url: url, contentsLoader: {
            await model.session?.journal(for: url)
        }) { journal, updateHandler in
            JournalView(journal: journal,
                        replyAction: { parentCid, text in
                Task {
                    let contents = try? await model
                        .postComment(on: journal,
                                     replytoCid: parentCid,
                                     contents: text)
                    updateHandler.update(with: contents)
                }
            })
        }
    }
}

struct RemoteJournalView_Previews: PreviewProvider {
    static var previews: some View {
        RemoteJournalView(url: FAJournal.demo.url)
            .environmentObject(Model.demo)
//            .preferredColorScheme(.dark)
    }
}
