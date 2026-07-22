//
//  Profiling.swift
//
//
//  Created by Ceylo on 22/09/2022.
//

import Foundation
import FALogging
#if canImport(os)
import os
#endif

private let subsystem = Bundle.main.bundleIdentifier ?? "FurAffinity"
let logger = PersistentLogger(subsystem: subsystem, category: "FAPages")

#if canImport(os)
private let signpostLog = Logger(subsystem: subsystem, category: "FAPages")
let signposter = OSSignposter(logger: signpostLog)
#else
// No os/Instruments on Android: a no-op signposter with the same call-site API.
let signposter = NoopSignposter()
#endif
