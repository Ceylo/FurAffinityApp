//
//  Profiling.swift
//  
//
//  Created by Ceylo on 22/09/2022.
//

import Foundation
import os

let FAKitLogger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FAKit")
let FAKitSignposter = OSSignposter(logger: FAKitLogger)
