//
//  LoadingFailedView.swift
//  FurAffinity
//
//  Created by Ceylo on 22/01/2023.
//

import SwiftUI

struct LoadingFailedView: View {
    var url: URL
    
    var text: String {
        """
    Here are some possible reasons:
    - Network connection was lost
    - furaffinity.net is experiencing an outage
    - The page doesn't exist anymore
    - The page contains data that could not be loaded
    - Viewing this page is prevented by your rating settings
    """
    }
    
    var body: some View {
        Centered {
            VStack(spacing: 20) {
                Text("Oops… loading failed.")
                    .font(.headline)
                Text(text)
                .font(.caption)
                .multilineTextAlignment(.leading)
                
                Link(url.description, destination: url)
            }
            .padding()
        }
    }
}

struct LoadingFailedView_Previews: PreviewProvider {
    static var previews: some View {
        LoadingFailedView(url: URL(string: "https://www.furaffinity.net/")!)
    }
}
