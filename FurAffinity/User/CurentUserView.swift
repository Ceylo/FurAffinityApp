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
    @Binding var navigationStack: NavigationPath
    
    var body: some View {
        Group {
            if let username = model.session?.username,
               let url = FAUser.url(for: username) {
                NavigationStack(path: $navigationStack) {
                    RemoteUserView(url: url)
                }
                .navigationDestination(for: FAURL.self) { nav in
                    view(for: nav)
                }
            } else {
                Text("Oops… invalid session")
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct CurentUserView_Previews: PreviewProvider {
    static var previews: some View {
        CurentUserView(navigationStack: .constant(.init()))
            .environmentObject(Model.demo)
    }
}
