//
//  CrashReportingSecrets.swift
//  FurAffinity
//
//  The Sentry DSN, one project for both platforms (split by `os.name`). A placeholder
//  in git: the release workflow (iOS) and the distribution stash (Android)
//  substitute the real value.
//

enum CrashReportingSecrets {
    static let placeholderDSN = "Your Sentry DSN"
    static let dsn = "Your Sentry DSN"
}
