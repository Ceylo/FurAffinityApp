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
    @State private var loadingFailed = false
    @State private var user: FAUser?
    @State private var description: AttributedString?
    private let bannerHeight = 100.0
    
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
    
    func view(for user: FAUser) -> some View {
        VStack(alignment: .leading) {
            GeometryReader { geometry in
                URLImage(user.bannerUrl) { progress in
                    Rectangle()
                        .foregroundColor(.white.opacity(0.1))
                } failure: { error, retry in
                    Image(systemName: "questionmark")
                        .resizable()
                } content: { image, info in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width,
                               height: bannerHeight,
                               alignment: .leading)
                        .clipped()
                        .transition(.opacity.animation(.default.speed(2)))
                }
            }
            .frame(height: bannerHeight)
            
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
    }
    
    var body: some View {
        ScrollView {
            if let user {
                view(for: user)
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

struct UserView_Previews: PreviewProvider {
    static var previews: some View {
        UserView(url: FAUser.url(for: "terriniss")!)
            .environmentObject(Model.demo)
//            .preferredColorScheme(.dark)
    }
}
