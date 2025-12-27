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
    @Environment(Model.self) private var model
    
    var body: some View {
        RemoteView(url: url, dataSource: { url in
            try await model.session.unwrap().journal(for: url)
        }) { journal, updateHandler in
            JournalView(journal: journal,
                        replyAction: { parentCid, reply in
                let updatedJournal = try await model
                    .postComment(
                        on: journal,
                        replytoCid: parentCid,
                        contents: reply.commentText
                    )
                updateHandler.update(with: updatedJournal)
            })
        }
    }
}

#Preview {
    withAsync({ try await Model.demo }) {
        RemoteJournalView(url: URL(string: "https://www.furaffinity.net/journal/10516170/")!)
            .environment($0)
    }
}
