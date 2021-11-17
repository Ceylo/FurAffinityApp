//
//  SettingsView.swift
//  FurAffinity
//
//  Created by Ceylo on 17/11/2021.
//

import SwiftUI
import FAKit

struct SettingsView: View {
    @Binding var session: FASession?
    
    var body: some View {
        List {
            Button("Disconnect from \(session?.displayUsername ?? "")", role: .destructive) {
                Task {
                    await FALoginView.logout()
//                    session = await FALoginView.makeSession()
                }
            }
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(session: .constant(OfflineFASession.default))
    }
}
