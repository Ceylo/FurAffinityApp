//
//  SubmissionFeedItemView.swift
//  FurAffinity
//
//  Created by Ceylo on 14/11/2021.
//

import SwiftUI
import FAKit
import URLImage

extension CGSize {
    var maxDimension: CGFloat { max(width, height) }
}

extension Color {
    static let borderOverlay = Color("BorderOverlay")
}

struct SubmissionFeedItemView: View {
    @EnvironmentObject var model: Model
    var submission: FASubmissionPreview
    @State private var avatarUrl: URL?
    
    var avatar: some View {
        ZStack {
            if let avatarUrl = avatarUrl {
                URLImage(avatarUrl) { progress in
                    Rectangle()
                        .foregroundColor(.white.opacity(0.1))
                } failure: { error, retry in
                    Image(systemName: "questionmark")
                        .resizable()
                } content: { image, info in
                    image
                        .resizable()
                        .transition(.opacity.animation(.default.speed(2)))
                }
                .environment(\.urlImageOptions, URLImageOptions(loadOptions: [.loadImmediately, .loadOnAppear, .cancelOnDisappear]))
            } else {
                Rectangle()
                    .foregroundColor(.white.opacity(0.1))
                    .task {
                        avatarUrl = await model.session?.avatarUrl(for: submission.author)
                    }
            }
        }
        .cornerRadius(5)
        .frame(width: 32, height: 32)
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color.borderOverlay.opacity(0.5), lineWidth: 1)
        }
            
    }
    
    var header: some View {
        HStack {
            avatar
            
            VStack(alignment: .leading) {
                Text(submission.displayAuthor)
                    .font(.headline)
                
                Text(submission.title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    var previewImage: some View {
        GeometryReader { geometry in
            // AsyncImage sometimes remains in empty phase when used in a List…
            URLImage(submission.bestThumbnailUrl(for: UInt(geometry.size.maxDimension))) { progress in
                Rectangle()
                    .foregroundColor(.white.opacity(0.1))
            } failure: { error, retry in
                Centered {
                    Text("Oops, image loading failed 😞")
                    Text(error.localizedDescription)
                        .font(.caption)
                }
            } content: { image, info in
                image
                    .resizable()
                    .transition(.opacity.animation(.default.speed(2)))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.borderOverlay, lineWidth: 1)
                    }
            }
            .environment(\.urlImageOptions, URLImageOptions(loadOptions: [.loadImmediately, .loadOnAppear, .cancelOnDisappear]))
        }
        .aspectRatio(CGFloat(submission.thumbnailWidthOnHeightRatio), contentMode: .fit)
        .cornerRadius(10)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            previewImage
        }
        .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 0))
    }
}

struct SubmissionFeedItemView_Previews: PreviewProvider {
    static var previews: some View {
        SubmissionFeedItemView(submission: OfflineFASession.default.submissionPreviews[0])
            .environmentObject(Model.demo)
            .preferredColorScheme(.dark)
    }
}
