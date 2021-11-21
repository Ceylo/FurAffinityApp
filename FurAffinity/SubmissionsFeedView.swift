//
//  SubmissionsFeedView.swift
//  FurAffinity
//
//  Created by Ceylo on 13/11/2021.
//

import SwiftUI
import FAKit

extension FASubmissionPreview: Identifiable {
    public var id: Int { sid }
}

struct SubmissionsFeedView: View {
    @EnvironmentObject var model: Model
    @State private var submissionPreviews = [FASubmissionPreview]()

    var body: some View {
        List($submissionPreviews) { $submission in
            SubmissionFeedItemView(submission: $submission)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 10, trailing: 0))
        }
        .listStyle(.plain)
        .task {
            submissionPreviews = await model.session?.submissionPreviews() ?? []
        }
        .refreshable {
            submissionPreviews = await model.session?.submissionPreviews() ?? []
        }
    }
}

struct SubmissionsFeedView_Previews: PreviewProvider {
    static var previews: some View {
        SubmissionsFeedView()
            .environmentObject(Model.demo)
            .preferredColorScheme(.dark)
    }
}
