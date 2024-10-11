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
    @EnvironmentObject var model: Model
    
    var body: some View {
        RemoteView(url: url) {
            await model.session?.journals(for: url)
        } contentsViewBuilder: { contents, updateHandler in
            UserJournalsView(journals: contents)
        }
    }
}

#Preview {
    NavigationStack {
        RemoteUserJournalsView(
            url: URL(string: "https://www.furaffinity.net/journals/tiaamaito/")!
        )
    }
    .environmentObject(Model.demo)
}
