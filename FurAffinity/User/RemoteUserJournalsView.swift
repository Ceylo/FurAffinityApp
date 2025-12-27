//
//  RemoteUserJournalsView.swift
//  FurAffinity
//
//  Created by Ceylo on 11/10/2024.
//

import SwiftUI
import FAKit

struct RemoteUserJournalsView: View {
    var url: URL
    @Environment(Model.self) private var model
    
    var body: some View {
        RemoteView(url: url) { url in
            try await model.session.unwrap().journals(for: url)
        } view: { journals, _ in
            UserJournalsView(journals: journals)
        }
    }
}

#Preview {
    withAsync({ try await Model.demo }) {
        NavigationStack {
            RemoteUserJournalsView(
                url: URL(string: "https://www.furaffinity.net/journals/tiaamaito/")!
            )
        }
        .environment($0)
    }
}
