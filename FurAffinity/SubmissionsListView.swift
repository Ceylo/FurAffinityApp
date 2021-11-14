//
//  SubmissionsListView.swift
//  FurAffinity
//
//  Created by Ceylo on 13/11/2021.
//

import SwiftUI
import FAPages
import FAKit

extension FASubmissionsPage.Submission: Identifiable {
    public var id: Int { sid }
}

struct SubmissionsListView: View {
    @Binding var session: FASession
    @State private var submissions = [FASubmissionsPage.Submission]()
    @Environment(\.displayScale) var displayScale: CGFloat
    
    func thumbnailUrl(for submission: FASubmissionsPage.Submission, size: CGFloat) -> URL {
        let url = submission.bestThumbnailUrl(for: UInt(size * displayScale))
        print(displayScale, url)
        return url
    }
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                let itemSize = geometry.size.width / 2
                let item = GridItem(.flexible(), spacing: 1)
                let columns = Array(repeating: item, count: 2)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 1) {
                    ForEach(submissions) { submission in
                        AsyncImage(url: thumbnailUrl(for: submission, size: itemSize)) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                                    .frame(width: itemSize, height: itemSize,
                                           alignment: .center)
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: itemSize, height: itemSize,
                                           alignment: .center)
                                    .clipped()
                            case .failure(let error):
                                Text("\(error.localizedDescription)")
                                    .frame(width: itemSize, height: itemSize,
                                           alignment: .center)
                            @unknown default:
                                fatalError()
                            }
                        }
                    }
                }
                .task {
                    submissions = await session.submissions()
                }
            }
        }
    }
}

struct SubmissionsListView_Previews: PreviewProvider {
    static var previews: some View {
        SubmissionsListView(session: .constant(FASession(sampleUsername: "Demo")))
    }
}
