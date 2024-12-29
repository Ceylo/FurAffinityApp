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
        RemoteView(url: url) { url in
            await model.session?.journals(for: url)
        } view: { journals, _ in
            UserJournalsView(journals: journals)
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
