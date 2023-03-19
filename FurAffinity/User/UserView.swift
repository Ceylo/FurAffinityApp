//
//  UserView.swift
//  FurAffinity
//
//  Created by Ceylo on 19/03/2023.
//

import SwiftUI
import FAKit
import URLImage

struct UserView: View {
    var url: URL
    @EnvironmentObject var model: Model
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
    }
    
    var body: some View {
        ScrollView {
            if let user {
                VStack(alignment: .leading) {
                    GeometryReader { geometry in
                        URLImage(user.bannerUrl) { image, info in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geometry.size.width, alignment: .leading)
                        }
                    }
                    .frame(height: 100)
                    
                    VStack(alignment: .leading) {
                        HStack {
                            AvatarView(avatarUrl: user.avatarUrl)
                                .frame(width: 32, height: 32)
                            Text(user.displayName)
                                .font(.title)
                        }
                        
                        if let description {
                            TextView(text: description, initialHeight: 300)
                        }
                    }
                    .padding(.horizontal)
                }
                .navigationTitle(user.displayName)
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ProgressView()
                    .task {
                        await loadUser(forceReload: false)
                    }
            }
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

struct UserView_Previews: PreviewProvider {
    static var previews: some View {
        UserView(url: FAUser.url(for: "terriniss")!)
            .environmentObject(Model.demo)
//            .preferredColorScheme(.dark)
    }
}
