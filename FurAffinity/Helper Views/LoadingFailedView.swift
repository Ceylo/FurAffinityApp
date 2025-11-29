//
//  LoadingFailedView.swift
//  FurAffinity
//
//  Created by Ceylo on 22/01/2023.
//

import FAKit
import SwiftUI

struct LoadingFailedView: View {
    var url: URL
    var error: LocalizedError
    
    var text: String {
        """
        Here are some possible reasons:
        • Network connection was lost
        • furaffinity.net is experiencing an outage
        • The page doesn't exist anymore
        • The page contains data that could not be loaded
        • Viewing this page is prevented by your rating settings
        """
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("😿 Oops… loading failed.")
                .font(.title)
            Link(url.description, destination: url)
            Text(text)
                .multilineTextAlignment(.leading)
            
            Divider()
            
            Text("🔴 Underlying error")
                .font(.headline)
            Text("\(error.localizedDescription)")
        }
        .padding(20)
    }
}

#Preview {
    LoadingFailedView(
        url: FAURLs.homeUrl,
        error: LocalizedErrorWrapper(ModelError.disconnected)
    )
}
