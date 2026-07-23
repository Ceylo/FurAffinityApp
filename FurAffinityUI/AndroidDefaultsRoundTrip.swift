//
//  AndroidDefaultsRoundTrip.swift
//  FurAffinityUI (Android)
//
//  Step-5 gate check: round-trips a Key<Bool> and a Key<FASearchQuery> (Codable)
//  through the ported Defaults on Android, logging the result. Confirms the fork
//  reads/writes and serializes on-device. Removed once real settings land.
//

import Foundation
import Defaults
import FAPages

extension FASearchQuery: Defaults.Serializable {}

enum AndroidDefaultsRoundTrip {
	private static let boolKey = Defaults.Key<Bool>("androidRoundtripBool", default: false)
	private static let queryKey = Defaults.Key<FASearchQuery>(
		"androidRoundtripQuery",
		default: .default
	)

	@MainActor
	static func run() {
		Defaults[boolKey] = true
		let boolOK = Defaults[boolKey] == true

		var query = FASearchQuery.default
		query.text = "dragon"
		Defaults[queryKey] = query
		let readBack = Defaults[queryKey]
		let queryOK = readBack.text == "dragon"

		logger.info("Defaults round-trip: Bool=\(boolOK ? "ok" : "FAIL"), FASearchQuery=\(queryOK ? "ok" : "FAIL") (text=\(readBack.text))")

		Defaults.reset(boolKey, queryKey)
	}
}
