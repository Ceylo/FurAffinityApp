//
//  Profiling.swift
//  
//
//  Created by Ceylo on 22/09/2022.
//

import Foundation
import os
import FALogging

let logger = PersistentLogger(subsystem: Bundle.main.bundleIdentifier!, category: "FAKit")
private let signpostLog = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FAKit")
let signposter = OSSignposter(logger: signpostLog)
