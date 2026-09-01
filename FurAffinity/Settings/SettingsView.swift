//
//  SettingsView.swift
//  FurAffinity
//
//  Created by Ceylo on 17/11/2021.
//

import SwiftUI
import FAKit
import FALogging
import Defaults

struct SettingsView: View {
    // Not private: skipstone can't bridge a private @State/@Environment.
    @Environment(Model.self) var model
    @State var dumpingLogs = false

    @Default(.animateAvatars) private var animateAvatars: Bool
    @Default(.addMessageToSharedItems) private var addMessageToSharedItems: Bool

    @State var cachedFileSize = "unknown"

    @State var cleaningCache = false

#if os(Android)
    // Not private: skipstone can't bridge a private @State.
    @State var http2Enabled = false
#endif

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Settings")
        }
    }

    private var content: some View {
        Form {
            Section("App information") {
                Link("Website", destination: URL(string: "https://furaffinity.app")!)
                Link("Privacy policy", destination: URL(string: "https://github.com/Ceylo/FurAffinityApp/blob/main/Privacy%20Policy.md")!)
                Link("Feature request & bug report", destination: URL(string: "https://github.com/Ceylo/FurAffinityApp/issues")!)
                LabeledContent("Current version", value: model.appInfo.currentVersion?.shortDescription ?? "Unknown")

                LabeledContent("Latest available version", value:  (model.appInfo.latestRelease?.version.shortDescription ?? "…"))

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
                if NotificationDelivery.isSupported {
                    NavigationLink("Notifications & Badges") {
                        NotificationSettingsView()
                    }
                }
                Toggle("Animate avatars", isOn: $animateAvatars)
            }
            
            Section {
                Toggle("Advertise the app", isOn: $addMessageToSharedItems)
            } header: {
                Text("Sharing")
            } footer: {
                Text("When enabled, sharing a link adds a message in order to let the recipient know about this app.")
            }

#if os(Android)
            // The measurement switch for the shared OkHttp client's protocol, which
            // both the page and the image pipelines ride. Debug builds only, and
            // gated on `android:debuggable` rather than `#if DEBUG`: skipstone skips
            // those blocks when generating the view bridge, so a compile-time fence
            // here would leave the @State above inert.
            //
            // Deliberately not a `Defaults.Key`: this lives in its own prefs file so
            // a script can flip it between arms without rewriting every other
            // setting, and so no iOS file gains a key for an Android-only knob.
            if AndroidAppInfo.isDebuggable {
                Section {
                    Toggle("HTTP/2 (debug)", isOn: Binding(
                        get: { http2Enabled },
                        set: { enabled in
                            http2Enabled = enabled
                            Task { await OkHttpTransport.setHTTP2Enabled(enabled) }
                        }
                    ))
                } header: {
                    Text("Network")
                } footer: {
                    Text("Takes effect immediately — the connection pool is evicted and redialled.")
                }
                .task {
                    http2Enabled = await OkHttpTransport.isHTTP2Enabled()
                }
            }
#endif
            
            if let session = model.session {
                Section("Account") {
                    Button("Disconnect from \(session.displayUsername)", role: .destructive) {
                        logout()
                    }
                }
            }
            
            Section {
                Menu {
                    Button("Last hour") { exportLogs(range: .lastHour) }
                    Button("Last 24 hours") { exportLogs(range: .last24Hours) }
                    Button("All") { exportLogs(range: .all) }
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

                Button("Clear Application Logs", role: .destructive) {
                    PersistentLogStore.shared.clear()
                }

                Button("Delete cached files (\(cachedFileSize))") {
                    cleaningCache = true
                    
                    Task {
                        await ImageCacheControl.clear()
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
        }
        .onAppear {
            updateCachedFileSize()
        }
    }
    
    private func exportLogs(range: LogExportRange) {
        dumpingLogs = true
        Task.detached {
            defer {
                Task { @MainActor in
                    dumpingLogs = false
                }
            }
            do {
                let fileUrl = try generateLogFile(range: range)
                await share([fileUrl])
            } catch {
                logger.error("Could not export logs: \(error)")
            }
        }
    }

    func updateCachedFileSize() {
        if let size = ImageCacheControl.formattedDiskSize() {
            cachedFileSize = size
        }
    }
    
    func logout() {
        Task { @MainActor in
            await withTaskCancellationHandler {
                do {
                    await clearLoginCookies()
                    try await Task.sleep(for: .milliseconds(100))
                    try await model.setSession(nil)
                } catch {
                    logger.error("Caught error while logging out: \(error)")
                }
            } onCancel: {
                logger.warning("logout was cancelled")
            }
        }
    }
}

#if !FA_SKIP_MODULE
#Preview {
    withAsync({ try await Model.demo }) {
        SettingsView()
            .environment($0)
    }
}
#endif
