//
//  SettingsView.swift
//  FurAffinity
//
//  Created by Ceylo on 17/11/2021.
//

import SwiftUI
import FAKit
import Alamofire
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

class AppInformation: ObservableObject {
    let currentVersion = Bundle.main.version
    @Published var latestRelease: Release?
    @Published var isUpToDate: Bool = true

    func fetch() {
        Task {
            latestRelease = try await AF
                .request("https://api.github.com/repos/Ceylo/FurAffinityApp/releases/latest")
                .serializingDecodable(Release.self)
                .response.result.get()
            
            if let latestVersion = latestRelease?.version {
                isUpToDate = latestVersion <= currentVersion
            } else {
                isUpToDate = true
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var model: Model
    @ObservedObject var appInfo = AppInformation()
    
    init() {
        appInfo.fetch()
    }
    
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
                       !appInfo.isUpToDate {
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
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(Model.demo)
    }
}
