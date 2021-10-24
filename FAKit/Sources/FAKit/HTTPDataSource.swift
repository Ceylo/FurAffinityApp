//
//  HTTPDataSource.swift
//  
//
//  Created by Ceylo on 24/10/2021.
//

import Foundation

public protocol HTTPDataSource {
    func httpData(from url: URL) async -> Data?
}

