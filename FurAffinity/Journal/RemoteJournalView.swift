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
    
    private func load() async -> JournalViewModel? {
        await model.session?
            .journal(for: url)
            .flatMap { JournalViewModel($0) }
    }
    
    var body: some View {
        RemoteView(url: url, contentsLoader: load) { journalData, updateHandler in
            JournalView(journal: journalData,
                        replyAction: { parentCid, text in
                Task {
                    let contents = try? await model
                        .postComment(on: journalData.journal,
                                     replytoCid: parentCid,
                                     contents: text)
                        .flatMap { JournalViewModel($0) }
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
