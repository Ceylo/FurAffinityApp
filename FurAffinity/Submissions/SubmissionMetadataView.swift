//
//  SubmissionMetadataView.swift
//  FurAffinity
//
//  Created by Ceylo on 02/03/2025.
//

import SwiftUI
import FAKit
import WrappingHStack

extension Rating {
    var displayDescription: String {
        switch self {
        case .general:
            "General"
        case .mature:
            "Mature"
        case .adult:
            "Adult"
        }
    }
}

struct SubmissionMetadataView: View {
    var metadata: FASubmission.Metadata
    
    var body: some View {
        List {
            Section {
                LabeledContent("Title", value: metadata.title)
                LabeledContent("Author", value: metadata.displayAuthor)
                LabeledContent("Submission date") {
                    DateTimeButton(
                        datetime: metadata.datetime,
                        naturalDatetime: metadata.naturalDatetime,
                        initialDisplayedDate: .absolute
                    )
                }
                LabeledContent("Size", value: metadata.size)
                LabeledContent("File Size", value: metadata.fileSize)
            }
            
            Section("Classification") {
                LabeledContent("Rating", value: metadata.rating.displayDescription)
                LabeledContent("Category", value: metadata.category)
                LabeledContent("Species", value: metadata.species)
            }
            
            Section("Statistics") {
                LabeledContent("Views", value: "\(metadata.viewCount)")
                LabeledContent("Comments", value: "\(metadata.commentCount)")
                LabeledContent("Favorites", value: "\(metadata.favoriteCount)")
            }
            
            if !metadata.keywords.isEmpty {
                Section("Keywords") {
                    WrappingHStack(metadata.keywords, lineSpacing: 5) {
                        Text($0)
                            .padding(5)
                            .padding(.horizontal, 5)
                            .background(Color.secondary.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            
            if !metadata.folders.isEmpty {
                Section("Folders") {
                    ForEach(metadata.folders) { folder in
                        FALink(destination: .gallery(url: folder.url)) {
                            Text(folder.title)
                        }
                    }
                }
            }
        }
        .navigationTitle("Submission Metadata")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        withAsync({ await FASubmission.demo.metadata }) { metadata in
            SubmissionMetadataView(
                metadata: metadata
            )
        }
    }
}
