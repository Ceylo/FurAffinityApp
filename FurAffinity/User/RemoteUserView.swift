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
    @State private var loadingFailed = false
    @State private var user: FAUser?
    @State private var description: AttributedString?
    
    private func loadUser(forceReload: Bool) async {
        guard let session = model.session else { return }
        guard user == nil || forceReload else { return }
        
        user = await session.user(for: url)
        
        if let user {
            description = AttributedString(FAHTML: user.htmlDescription)?
                .convertingLinksForInAppNavigation()
        }
        loadingFailed = user == nil
    }
    
    var body: some View {
        ScrollView {
            if let user {
                UserView(user: user, description: description)
            } else if loadingFailed {
                LoadingFailedView(url: url)
            }
        }
        .task {
            await loadUser(forceReload: false)
        }
        .refreshable {
            Task {
                await loadUser(forceReload: true)
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

struct RemoteUserView_Previews: PreviewProvider {
    static var previews: some View {
        RemoteUserView(url: FAUser.url(for: "terriniss")!)
            .environmentObject(Model.demo)
//            .preferredColorScheme(.dark)
    }
}
