//
//  HeaderView.swift
//  FurAffinity
//
//  Created by Ceylo on 08/12/2021.
//

import SwiftUI
import FAKit
import URLImage

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

struct SubmissionTitledHeaderView_Previews: PreviewProvider {
    static var previews: some View {
        TitledHeaderView(title: "Great Content")
            .previewLayout(.sizeThatFits)
            .preferredColorScheme(.dark)
            
    }
}
