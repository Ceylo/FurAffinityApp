//
//  SaveButton.swift
//  FurAffinity
//
//  Created by Ceylo on 27/11/2021.
//

import SwiftUI
import Combine

fileprivate extension ActionState {
    var saveButtonImageName: String {
        switch self {
        case .idle, .inProgress:
            return "square.and.arrow.down"
        case .succeeded:
            return "checkmark"
        }
    }
}

struct SaveButton: View {
    var state: ActionState
    var action: (() -> Void)
    
    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: state.saveButtonImageName)
                .resizable()
                .tint(Color.buttonTint)
                .aspectRatio(contentMode: .fit)
                .padding()
                .transition(.opacity.animation(.default))
        }
    }
}

#Preview {
    ForEach([false, true], id: \.self) { disabled in
        HStack {
            ForEach(ActionState.allCases) { state in
                SaveButton(state: state) {
                }
                .frame(width: 60, height: 60)
                .disabled(disabled)
            }
        }
    }
}
