//
//  SubmissionsFeedView.swift
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

struct SubmissionsFeedView: View {
    @EnvironmentObject var model: Model
    @State private var submissions = [FASubmissionsPage.Submission]()

    var body: some View {
        List($submissions) { $submission in
            SubmissionFeedItemView(submission: $submission)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 10, trailing: 0))
        }
        .listStyle(.plain)
        .task {
            submissions = await model.session?.submissions() ?? []
        }
        .refreshable {
            submissions = await model.session?.submissions() ?? []
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
