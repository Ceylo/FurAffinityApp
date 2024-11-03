//
//  HeaderView.swift
//  FurAffinity
//
//  Created by Ceylo on 08/12/2021.
//

import SwiftUI
import FAKit

struct TitledHeaderView: View {
    var title: String
    
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            Spacer()
        }
    }
}

extension TitledHeaderView: SubmissionHeaderView {
    init(preview: FAKit.FASubmissionPreview, avatarUrl: URL?) {
        self.init(
            title: preview.title
        )
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    TitledHeaderView(title: "Great Content")
        .preferredColorScheme(.dark)
}
