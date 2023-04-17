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
    @State private var loadingFailed = false
    @State private var journal: FAJournal?
    @State private var description: AttributedString?
    
    private func load(forceReload: Bool) async {
        guard let session = model.session else { return }
        guard journal == nil || forceReload else { return }
        
        journal = await session.journal(for: url)
        if let journal {
            description = AttributedString(FAHTML: journal.htmlDescription)?
                .convertingLinksForInAppNavigation()
        }
        loadingFailed = journal == nil
    }
    
    var body: some View {
        Group {
            if let journal {
                ScrollView {
                    JournalView(journal: journal, description: description,
                                replyAction: { parentCid, text in
//                        Task {
//                            self.submission = try await model
//                                .postComment(on: submission,
//                                             replytoCid: parentCid,
//                                             contents: text)
//                        }
                    })
                }
            } else if loadingFailed {
                ScrollView {
                    LoadingFailedView(url: url)
                }
            } else {
                ProgressView()
            }
        }
        .task {
            await load(forceReload: false)
        }
        .refreshable {
            Task {
                await load(forceReload: true)
            }
        }
        .toolbar {
            ToolbarItem {
                Link(destination: url) {
                    Image(systemName: "safari")
                }
            }
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
