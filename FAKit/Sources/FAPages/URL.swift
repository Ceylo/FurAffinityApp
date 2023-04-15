//
//  URL.swift
//  
//
//  Created by Ceylo on 15/04/2023.
//

import Foundation

public extension URL {
    init(unsafeString: String) throws {
        self = try URLComponents(string: unsafeString).unwrap()
            .url.unwrap()
    }
}
