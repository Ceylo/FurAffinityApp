//
//  CurrentUserView.swift
//  FurAffinity
//
//  Created by Ceylo on 19/03/2023.
//

import SwiftUI
import FAKit

struct CurrentUserView: View {
    @EnvironmentObject var model: Model
    
    var body: some View {
        Group {
            if let session = model.session,
               let url = FAURLs.userpageUrl(for: session.username) {
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

struct CurentUserView_Previews: PreviewProvider {
    static var previews: some View {
        CurrentUserView()
            .environmentObject(Model.demo)
    }
}
