//
//  SettingsView.swift
//  FurAffinity
//
//  Created by Ceylo on 17/11/2021.
//

import SwiftUI
import FAKit
import Kingfisher
import Defaults

struct SettingsView: View {
    @EnvironmentObject var model: Model
    @State private var dumpingLogs = false
    
    @Default(.animateAvatars) private var animateAvatars: Bool
    @Default(.notifySubmissionComments) private var notifySubmissionComments
    @Default(.notifyJournalComments) private var notifyJournalComments
    @Default(.notifyShouts) private var notifyShouts
    @Default(.notifyJournals) private var notifyJournals
    
    @State private var cachedFileSize = "unknown"
    
    @State private var cleaningCache = false
    
    var body: some View {
        Form {
            Section("App information") {
                Link("Website", destination: URL(string: "https://furaffinity.app")!)
                Link("Privacy policy", destination: URL(string: "https://github.com/Ceylo/FurAffinityApp/blob/main/Privacy%20Policy.md")!)
                Link("Feature request & bug report", destination: URL(string: "https://github.com/Ceylo/FurAffinityApp/issues")!)
                Text("Current version: " + model.appInfo.currentVersion.description)
                Text("Latest available version: "
                     + (model.appInfo.latestRelease?.tag_name ?? "…"))
                
                if let latestRelease = model.appInfo.latestRelease,
                   let isUpToDate = model.appInfo.isUpToDate,
                   !isUpToDate {
                    Text(latestRelease.body.trimmingCharacters(in: .newlines))
                        .font(.caption)
                    if let url = URL(string: latestRelease.html_url) {
                        Link(destination: url) {
                            Label("Get " + latestRelease.name, systemImage: "square.and.arrow.down")
                        }
                        .padding(.bottom, 5)
                    }
                }
            }
            
            Section("Display") {
                Toggle("Animate avatars", isOn: $animateAvatars)
            }
            
            Section {
                Toggle("Submission comments", isOn: $notifySubmissionComments)
                Toggle("Journal comments", isOn: $notifyJournalComments)
                Toggle("Shouts", isOn: $notifyShouts)
                Toggle("Journals", isOn: $notifyJournals)
            } header: {
                Text("Notification badge")
            } footer: {
                Text("iOS notifications are not supported. These settings change the badge displayed on the Notifications tab.")
            }
            
            Section {
                Button {
                    dumpingLogs = true
                    Task.detached {
                        defer {
                            Task { @MainActor in
                                dumpingLogs = false
                            }
                        }
                        if let fileUrl = try? generateLogFile() {
                            await share([fileUrl])
                        }
                    }
                } label: {
                    HStack {
                        Text("Export Application Logs")
                        Spacer()
                        if dumpingLogs {
                            ProgressView()
                        }
                    }
                }
                .disabled(dumpingLogs)
                
                Button("Delete cached files (\(cachedFileSize))") {
                    cleaningCache = true
                    
                    Task {
                        await ImageCache.default.clearDiskCache()
                        updateCachedFileSize()
                        cleaningCache = false
                    }
                }
                .disabled(cleaningCache)
            } header: {
                Text("Advanced")
            } footer: {
                Text("This cache allows faster contents display. Clearing it will cause images to be downloaded again from furaffinity.net when needed.")
            }

            
            if let session = model.session {
                Section("Account") {
                    Button("Disconnect from \(session.displayUsername)", role: .destructive) {
                        Task {
                            await FALoginView.logout()
                            let newSession = await FALoginView.makeSession()
                            assert(newSession == nil)
                            DispatchQueue.main.async {
                                model.clearSessionData()
                                model.session = newSession
                            }
                        }
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            model.updateAppInfoIfNeeded()
        }
        .onAppear {
            updateCachedFileSize()
        }
    }
    
    func updateCachedFileSize() {
        if let size = try? ImageCache.default.diskStorage.totalSize() {
            cachedFileSize = ByteCountFormatter.string(
                fromByteCount: Int64(size),
                countStyle: .file
            )
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(Model.demo)
    }
}
