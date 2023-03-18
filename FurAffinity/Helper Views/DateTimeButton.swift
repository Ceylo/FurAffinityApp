//
//  DateTimeButton.swift
//  FurAffinity
//
//  Created by Ceylo on 18/03/2023.
//

import SwiftUI

struct DateTimeButton: View {
    var datetime: String
    var naturalDatetime: String
    @State private var showExactDatetime = false
    
    var body: some View {
        Button(showExactDatetime ? datetime : naturalDatetime) {
            showExactDatetime.toggle()
        }
        .foregroundStyle(.secondary)
        .font(.subheadline)
    }
}

struct DateTimeButton_Previews: PreviewProvider {
    static var previews: some View {
        DateTimeButton(datetime: "Apr 7th, 2022, 11:58 AM",
                       naturalDatetime: "8 months ago")
    }
}
