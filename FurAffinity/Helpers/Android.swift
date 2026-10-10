//
//  Android.swift
//  FurAffinity
//
//  Created by Ceylo on 10/10/2026.
//

#if FA_SKIP_MODULE
let isSkipBuild = true
#else
let isSkipBuild = false
#endif

#if os(Android)
let isAndroidBuild = true
#else
let isAndroidBuild = false
#endif
