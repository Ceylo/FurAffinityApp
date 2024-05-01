//
//  RemoteUserView.swift
//  FurAffinity
//
//  Created by Ceylo on 19/03/2023.
//

import SwiftUI
import FAKit
import URLImage

struct RemoteUserView: View {
    var url: URL
    @EnvironmentObject var model: Model
    @State private var description: AttributedString?
    
    private func loadUser() async -> FAUser? {
        guard let session = model.session else { return nil }
        
        let user = await session.user(for: url)
        if let user {
            description = AttributedString(FAHTML: user.htmlDescription)?
                .convertingLinksForInAppNavigation()
        }
        return user
    }
    
    var body: some View {
        RemoteView(url: url, contentsLoader: loadUser) { user, updateHandler in
            UserView(
                user: user,
                description: $description,
                toggleWatchAction: {
                    Task {
                        let updatedUser = await model.session?.toggleWatch(for: user)
                        updateHandler.update(with: updatedUser)
                    }
                }
            )
        }
    }
}

struct RemoteUserView_Previews: PreviewProvider {
    static var previews: some View {
        RemoteUserView(url: FAURLs.userpageUrl(for: "terriniss")!)
            .environmentObject(Model.demo)
//            .preferredColorScheme(.dark)
    }
}
