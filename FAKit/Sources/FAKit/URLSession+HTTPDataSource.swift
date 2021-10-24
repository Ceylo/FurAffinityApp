//
//  URLSession+HTTPDataSource.swift
//  
//
//  Created by Ceylo on 24/10/2021.
//

import Foundation

extension URLSession: HTTPDataSource {
    public func httpData(from url: URL) async -> Data? {
        do {
            print(#function, ":", url)
            let (dat, response) = try await self.data(from: url, delegate: nil)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let mimeType = httpResponse.mimeType, mimeType == "text/html"
            else { return nil }
            
            return dat
        } catch {
            return nil
        }
    }
}
