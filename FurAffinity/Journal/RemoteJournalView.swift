//
//  RemoteJournalView.swift
//  FurAffinity
//
//  Created by Ceylo on 19/03/2023.
//

import SwiftUI
import FAKit

struct RemoteJournalView: View {
    var url: URL
    @EnvironmentObject var model: Model
    
    var body: some View {
        RemoteView(url: url, dataSource: { url in
            await model.session?.journal(for: url)
        }) { journal, updateHandler in
            JournalView(journal: journal,
                        replyAction: { parentCid, text in
                let updatedJournal = try? await model
                    .postComment(on: journal,
                                 replytoCid: parentCid,
                                 contents: text)
                updateHandler.update(with: updatedJournal)
                return updatedJournal != nil
            })
        }
    }
}

#Preview {
    RemoteJournalView(url: URL(string: "https://www.furaffinity.net/journal/10516170/")!)
        .environmentObject(Model.demo)
}
