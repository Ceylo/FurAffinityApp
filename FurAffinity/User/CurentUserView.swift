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
        if let username = model.session?.username {
            UserView(username: username)
        } else {
            Text("Oops… invalid session")
        }
    }
}

struct CurentUserView_Previews: PreviewProvider {
    static var previews: some View {
        CurentUserView(navigationStack: .constant(.init()))
            .environmentObject(Model.demo)
    }
}
