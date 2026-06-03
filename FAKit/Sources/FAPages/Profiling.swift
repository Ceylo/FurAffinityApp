//
//  Profiling.swift
//  
//
//  Created by Ceylo on 22/09/2022.
//

import os
import Foundation
import FALogging

let logger = PersistentLogger(subsystem: Bundle.main.bundleIdentifier!, category: "FAPages")
private let signpostLog = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FAPages")
let signposter = OSSignposter(logger: signpostLog)
