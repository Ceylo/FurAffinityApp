//
//  CrashTestSite.swift
//  FAKit
//
//  A deliberate crash inside FAKit, so crash-report verification proves a second
//  library's symbols resolve too. Only `CrashTest` (app target) calls it; see
//  Scripts/check-crash-reporting.sh, which greps the marker for the expected line.
//

public enum CrashTestSite {
    @inline(never)
    public static func forceUnwrapNil(_ value: String?) -> Int {
        value!.count // CRASH-TEST-SITE swiftForceUnwrapFAKit
    }
}
