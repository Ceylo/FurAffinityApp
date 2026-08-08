//
//  FADefault.swift
//  FurAffinity
//
//  The app's defaults-backed property wrapper, so shared settings screens declare a
//  toggle once instead of behind an `#if`. On iOS it is exactly Defaults' `@Default`;
//  Android re-declares it over its own storage in
//  FurAffinityUI/AndroidFADefault.swift (which is why this file is not symlinked into
//  the Skip module).
//

import Defaults

typealias FADefault = Default
