//
//  UserJournalsView.swift
//  FurAffinity
//
//  Created by Ceylo on 11/10/2024.
//

import SwiftUI
import FAKit

struct JournalItemView: View {
    var journal: FAUserJournals.Journal
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(journal.title)
                    .font(.headline)
            }
            
            HStack {
                Spacer()
                DateTimeButton(datetime: journal.datetime,
                               naturalDatetime: journal.naturalDatetime)
            }
            .foregroundStyle(.secondary)
            .font(.subheadline)
        }
    }
}

struct UserJournalsView: View {
    var journals: FAUserJournals
    
    var body: some View {
        List(journals.journals) { journal in
            NavigationLink(value: FAURL.journal(url: journal.url)) {
                JournalItemView(journal: journal)
            }
        }
        .listStyle(.plain)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("\(journals.displayAuthor)'s journals")
        .swap(when: journals.journals.isEmpty) {
            VStack(spacing: 10) {
                Text("It's a bit empty in here.")
                    .font(.headline)
                Text("There's no journal from \(journals.displayAuthor) to read yet.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
    }
}

#Preview("With journals") {
    NavigationStack {
        UserJournalsView(journals: .demo)
    }
}

#Preview("With no journal") {
    NavigationStack {
        UserJournalsView(journals: .empty)
    }
}
