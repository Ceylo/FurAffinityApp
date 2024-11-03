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
        case .failed:
            return "exclamationmark.circle"
        }
    }
    
    var saveButtonColor: Color {
        return self == .failed ? Color.red : Color.accentColor
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
                .foregroundColor(state.saveButtonColor)
                .aspectRatio(contentMode: .fit)
                .padding()
                .transition(.opacity.animation(.default))
        }
    }
}

#Preview {
    HStack {
        ForEach(ActionState.allCases) { state in
            SaveButton(state: state) {
            }
            .frame(width: 60, height: 60)
        }
    }
}
