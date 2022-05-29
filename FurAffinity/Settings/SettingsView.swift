//
//  SettingsView.swift
//  FurAffinity
//
//  Created by Ceylo on 17/11/2021.
//

import SwiftUI
import FAKit

struct SettingsView: View {
    @EnvironmentObject var model: Model
    
    var body: some View {
        List {
            if let session = model.session {
                Button("Disconnect from \(session.displayUsername)", role: .destructive) {
                    Task {
                        await FALoginView.logout()
                        let newSession = await FALoginView.makeSession()
                        DispatchQueue.main.async {
                            model.session = newSession
                        }
                    }
                }
            }
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(Model.demo)
    }
}
