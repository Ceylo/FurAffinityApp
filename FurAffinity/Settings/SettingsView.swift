//
//  SettingsView.swift
//  FurAffinity
//
//  Created by Ceylo on 17/11/2021.
//

import SwiftUI
import FAKit
import Version

struct Release: Decodable {
    let html_url: String
    let draft: Bool
    let prerelease: Bool
    let published_at: String
    let tag_name: String
    let name: String
    let body: String
    
    var version: Version {
        Version(tolerant: tag_name) ?? .null
    }
}

@MainActor
class AppInformation: ObservableObject {
    let currentVersion = Bundle.main.version
    @Published var latestRelease: Release?
    @Published var isUpToDate: Bool?

    func fetch() {
        Task {
            let url = URL(string: "https://api.github.com/repos/Ceylo/FurAffinityApp/releases/latest")!
            if let data = await URLSession.shared.httpData(from: url, cookies: nil) {
                let release = try JSONDecoder().decode(Release.self, from: data)
                isUpToDate = release.version <= currentVersion
                latestRelease = release
            } else {
                latestRelease = nil
                isUpToDate = nil
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var model: Model
    @ObservedObject var appInfo = AppInformation()
    
    var body: some View {
        Form {
            Section("App information") {
                Link("Website", destination: URL(string: "https://github.com/Ceylo/FurAffinityApp")!)
                Link("Feature request & bug report", destination: URL(string: "https://github.com/Ceylo/FurAffinityApp/issues")!)
                Text("Current version: " + appInfo.currentVersion.description)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Latest available version: "
                         + (appInfo.latestRelease?.tag_name ?? "…"))
                    
                    if let latestRelease = appInfo.latestRelease,
                       let isUpToDate = appInfo.isUpToDate,
                       !isUpToDate {
                        Text(latestRelease.body.trimmingCharacters(in: .newlines))
                            .font(.caption)
                        if let url = URL(string: latestRelease.html_url) {
                            Link("Get " + latestRelease.name, destination: url)
                                .padding(.bottom, 5)
                        }
                    }
                }
            }
            
            if let session = model.session {
                Section("Account") {
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
        .onAppear {
            appInfo.fetch()
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(Model.demo)
    }
}
