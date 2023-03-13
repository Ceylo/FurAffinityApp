//
//  SubmissionLoadingFailedView.swift
//  FurAffinity
//
//  Created by Ceylo on 22/01/2023.
//

import SwiftUI
import FAKit

struct SubmissionLoadingFailedView: View {
    var url: URL
    
    var body: some View {
        Centered {
            VStack(spacing: 20) {
                Text("Oops… submission loading failed.")
                    .font(.headline)
                Text("""
    Here are some possible reasons:
    - Network connection was lost
    - furaffinity.net is experiencing an outage
    - The submission doesn't exist anymore
    - The submission contains data that could not be loaded
    """)
                .font(.caption)
                .multilineTextAlignment(.leading)
                
                Link(url.description, destination: url)
            }
            .padding()
        }
    }
}

struct SubmissionLoadingFailedView_Previews: PreviewProvider {
    static var previews: some View {
        SubmissionLoadingFailedView(url: FASubmissionPreview.demo.url)
    }
}
