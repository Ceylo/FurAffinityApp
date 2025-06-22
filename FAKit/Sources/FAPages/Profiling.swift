//
//  Profiling.swift
//  
//
//  Created by Ceylo on 22/09/2022.
//

import os
import Foundation

let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FAPages")
let signposter = OSSignposter(logger: logger)
