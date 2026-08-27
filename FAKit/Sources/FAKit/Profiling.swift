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
// Android has no `os`; OSCompat vends the same surface, and its name matters —
// see OSCompat.swift.
import OSCompat
#endif

private let subsystem = FALogSubsystem.identifier
let logger = PersistentLogger(subsystem: subsystem, category: "FAKit")

private let signpostLog = Logger(subsystem: subsystem, category: "FAKit")
let signposter = OSSignposter(logger: signpostLog)
