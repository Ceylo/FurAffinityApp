//
//  Secrets.swift
//  FurAffinity
//
//  Created by Ceylo on 12/01/2023.
//
//  Placeholders in git: CI seds the real values in, and a local distribution build
//  gets them from the distribution stash.
//

enum Secrets {
    static let placeholderApiKey = "Your App Secret"
    static let amplitudeApiKey = "Your App Secret"

    /// One Sentry project for both platforms, split by `os.name`.
    static let placeholderSentryDSN = "Your Sentry DSN"
    static let sentryDSN = "Your Sentry DSN"
}
