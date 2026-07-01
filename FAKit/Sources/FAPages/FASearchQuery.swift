//
//  FASearchQuery.swift
//  FAKit
//
//  Created by Ceylo on 21/06/2026.
//

import Foundation

/// A full description of a furaffinity.net search, mirroring the fields of the
/// `/search/` form. `Codable` so the whole query can be persisted (remembered
/// across launches) via `Defaults`.
public struct FASearchQuery: Codable, Sendable, Equatable {
    public enum SortOrder: String, Codable, Sendable, CaseIterable {
        case relevancy
        case date
        case popularity
    }

    public enum SortDirection: String, Codable, Sendable, CaseIterable {
        case ascending = "asc"
        case descending = "desc"
    }

    /// Preset date ranges. The form also offers a manual from/to range, deferred
    /// to a later iteration.
    public enum DateRange: String, Codable, Sendable, CaseIterable {
        case oneDay = "1day"
        case threeDays = "3days"
        case sevenDays = "7days"
        case thirtyDays = "30days"
        case ninetyDays = "90days"
        case oneYear = "1year"
        case threeYears = "3years"
        case fiveYears = "5years"
        case all
    }

    public enum ContentType: String, Codable, Sendable, CaseIterable {
        case art
        case music
        case flash
        case story
        case photo
        case poetry
    }

    /// The gender checkboxes have no `name` in the page markup — the site JS
    /// instead appends the selected values to the `q` text as an
    /// `@keywords <values…>` operator (see `FAURLs.searchUrl`).
    public enum Gender: String, Codable, Sendable, CaseIterable {
        case male
        case female
        case transMale = "trans_male"
        case transFemale = "trans_female"
        case intersex
        case nonBinary = "non_binary"
    }

    public var text: String
    public var sortOrder: SortOrder
    public var sortDirection: SortDirection
    public var dateRange: DateRange
    public var ratings: Set<Rating>
    public var contentTypes: Set<ContentType>
    public var genders: Set<Gender>
    /// Tags searched against a submission's **tags only** (folded into the
    /// `@keywords` operator). Arrays preserve user-entered order.
    public var includedTags: [String]
    /// Tags that must **not** be present (emitted as `!tag` under `@keywords`).
    public var excludedTags: [String]
    public var page: Int

    public init(
        text: String,
        sortOrder: SortOrder,
        sortDirection: SortDirection,
        dateRange: DateRange,
        ratings: Set<Rating>,
        contentTypes: Set<ContentType>,
        genders: Set<Gender>,
        includedTags: [String],
        excludedTags: [String],
        page: Int
    ) {
        self.text = text
        self.sortOrder = sortOrder
        self.sortDirection = sortDirection
        self.dateRange = dateRange
        self.ratings = ratings
        self.contentTypes = contentTypes
        self.genders = genders
        self.includedTags = includedTags
        self.excludedTags = excludedTags
        self.page = page
    }

    /// Mirrors the `/search/` form defaults: relevancy, descending, last 5 years,
    /// all ratings and content types on, no tag filters, first page. The app
    /// always searches in extended mode (required by the `@keywords`/`!` operators).
    public static let `default` = FASearchQuery(
        text: "",
        sortOrder: .relevancy,
        sortDirection: .descending,
        dateRange: .fiveYears,
        ratings: Set(Rating.allCases),
        contentTypes: Set(ContentType.allCases),
        genders: [],
        includedTags: [],
        excludedTags: [],
        page: 1
    )
}

extension Rating {
    /// The `rating-<suffix>` checkbox name used by the `/search/` form.
    var searchParamSuffix: String {
        switch self {
        case .general: "general"
        case .mature: "mature"
        case .adult: "adult"
        }
    }

    /// Maps a `/search/` form checkbox `name` (`rating-general` etc.) to a rating.
    public init?(searchParamName: String) {
        switch searchParamName {
        case "rating-general": self = .general
        case "rating-mature": self = .mature
        case "rating-adult": self = .adult
        default: return nil
        }
    }
}
