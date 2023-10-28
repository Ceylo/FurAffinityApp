//
//  CurentUserView.swift
//  FurAffinity
//
//  Created by Ceylo on 19/03/2023.
//

import SwiftUI
import FAKit

struct CurentUserView: View {
    @EnvironmentObject var model: Model
    
    var body: some View {
        Group {
            if let username = model.session?.username,
               let url = FAURLs.userpageUrl(for: username) {
                RemoteUserView(url: url)
            } else {
                Text("Oops… invalid session")
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CurentUserView_Previews: PreviewProvider {
    static var previews: some View {
        CurentUserView()
            .environmentObject(Model.demo)
    }
}
