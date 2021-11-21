//
//  Model.swift
//  FurAffinity
//
//  Created by Ceylo on 21/11/2021.
//

import SwiftUI
import FAKit

class Model: ObservableObject {
    @Published var session: FASession?
    
    init(session: FASession? = nil) {
        self.session = session
    }
}
