//
//  DateTimeButton.swift
//  FurAffinity
//
//  Created by Ceylo on 18/03/2023.
//

import SwiftUI

struct DateTimeButton: View {
    enum DisplayedDate {
        case natural
        case absolute
    }
    
    var datetime: String
    var naturalDatetime: String
    var initialDisplayedDate: DisplayedDate = .natural
    @State private var showExactDatetime = false
    
    private var dateToDisplay: String {
        (initialDisplayedDate == .natural) == showExactDatetime ? datetime : naturalDatetime
    }
    
    var body: some View {
        Button(dateToDisplay) {
            showExactDatetime.toggle()
        }
        .foregroundStyle(.secondary)
        .font(.subheadline)
        // 🫠 https://forums.developer.apple.com/forums/thread/747558
        .buttonStyle(BorderlessButtonStyle())
    }
}

#Preview {
    DateTimeButton(datetime: "Apr 7th, 2022, 11:58 AM",
                   naturalDatetime: "8 months ago",
                   initialDisplayedDate: .natural)
}
