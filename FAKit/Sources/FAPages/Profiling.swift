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
#else
// Android has no `os`; OSCompat vends the same Logger/OSSignposter surface.
// It must NOT be named `os`: a module by that name makes canImport(os) true for
// every target in the build, and whatever compiles after it takes its Apple
// branch and fails (see Android/README.md § The `os` compatibility module).
import OSCompat
#endif

private let subsystem = Bundle.main.bundleIdentifier ?? "FurAffinity"
let logger = PersistentLogger(subsystem: subsystem, category: "FAPages")

private let signpostLog = Logger(subsystem: subsystem, category: "FAPages")
let signposter = OSSignposter(logger: signpostLog)
