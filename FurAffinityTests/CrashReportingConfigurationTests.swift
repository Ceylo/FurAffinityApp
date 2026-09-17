//
//  CrashReportingConfigurationTests.swift
//  FurAffinityTests
//

import Testing

@testable import Fur_Affinity

struct CrashReportingConfigurationTests {
    private let dsn = "https://key@o1.ingest.de.sentry.io/2"

    @Test func realDSN_buildsReleaseAndEnvironment() throws {
        let configuration = try #require(CrashReportingConfiguration.make(
            dsn: dsn, appID: "com.example.fa", version: "1.19.0",
            configuration: .release, enabled: true, enabledSince: .distantPast
        ))
        #expect(configuration.dsn == dsn)
        #expect(configuration.release == "com.example.fa@1.19.0")
        #expect(configuration.environment == "release")
        #expect(configuration.reportsSince == .distantPast)
    }

    @Test func missingAppID_fallsBackToAppName() throws {
        let configuration = try #require(CrashReportingConfiguration.make(
            dsn: dsn, appID: nil, version: "1.0", configuration: .debug, enabled: true, enabledSince: .distantPast
        ))
        #expect(configuration.release == "FurAffinity@1.0")
        #expect(configuration.environment == "debug")
    }

    @Test func placeholderDSN_startsNothing() {
        #expect(CrashReportingConfiguration.make(
            dsn: CrashReportingSecrets.placeholderDSN, appID: "id", version: "1.0",
            configuration: .release, enabled: true, enabledSince: .distantPast
        ) == nil)
    }

    @Test func optedOut_startsNothing() {
        #expect(CrashReportingConfiguration.make(
            dsn: dsn, appID: "id", version: "1.0", configuration: .release, enabled: false, enabledSince: .distantPast
        ) == nil)
    }
}
