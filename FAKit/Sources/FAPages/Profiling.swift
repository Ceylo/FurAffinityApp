//
//  Profiling.swift
//
//
//  Created by Ceylo on 22/09/2022.
//

import Foundation
import FALogging
import os

private let subsystem = Bundle.main.bundleIdentifier ?? "FurAffinity"
let logger = PersistentLogger(subsystem: subsystem, category: "FAPages")

private let signpostLog = Logger(subsystem: subsystem, category: "FAPages")
let signposter = OSSignposter(logger: signpostLog)
