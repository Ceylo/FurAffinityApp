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
    @Binding var session: FASession
    @State private var submissions = [FASubmissionsPage.Submission]()

    var body: some View {
        List($submissions) { $submission in
            SubmissionFeedItemView(submission: $submission)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 10, trailing: 0))
        }
        .listStyle(.plain)
        .task {
            submissions = await session.submissions()
        }
        .refreshable {
            submissions = await session.submissions()
        }
    }
}

struct SubmissionsFeedView_Previews: PreviewProvider {
    static var previews: some View {
        SubmissionsFeedView(session: .constant(OfflineFASession.default))
            .preferredColorScheme(.dark)
    }
}
