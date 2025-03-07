//
//  TestData.swift
//  
//
//  Created by Ceylo on 17/10/2021.
//

import Foundation

func testData(_ filename: String) -> Data {
    let url = Bundle.module
        .url(forResource: filename, withExtension: nil, subdirectory: "data")
    guard let url else {
        return Data()
    }
    return try! Data(contentsOf: url)
}
