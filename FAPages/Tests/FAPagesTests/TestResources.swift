//
//  TestResources.swift
//  
//
//  Created by Ceylo on 17/10/2021.
//

import Foundation

func htmlPath(_ filename: String) -> URL {
    Bundle.module
        .url(forResource: filename, withExtension: "html", subdirectory: "data")!
}
