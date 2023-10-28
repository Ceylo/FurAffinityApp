//
//  DatetimePair.swift
//  FurAffinity
//
//  Created by Ceylo on 28/10/2023.
//

import Foundation

struct DatetimePair {
    var datetime: String
    var naturalDatetime: String
    
    init(_ datetime: String, _ naturalDatetime: String) {
        self.datetime = datetime
        self.naturalDatetime = naturalDatetime
    }
}
