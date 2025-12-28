//
//  CurrentUserView.swift
//  FurAffinity
//
//  Created by Ceylo on 19/03/2023.
//

import SwiftUI
import FAKit

struct CurrentUserView: View {
    @Environment(Model.self) private var model
    
    var body: some View {
        Group {
            if let session = model.session,
               let url = try? FAURLs.userpageUrl(for: session.username) {
                RemoteUserView(
                    url: url,
                    previewData: .init(
                        username: session.username,
                        displayName: session.displayUsername,
                        avatarUrl: FAURLs.avatarUrl(for: session.username)
                    )
                )
            } else {
                Text("Oops… invalid session")
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    withAsync({ try await Model.demo }) {
        CurrentUserView()
            .environment($0)
            .environment($0.errorStorage)
    }
}
