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
let logger = PersistentLogger(subsystem: subsystem, category: "FAKit")

private let signpostLog = Logger(subsystem: subsystem, category: "FAKit")
let signposter = OSSignposter(logger: signpostLog)
