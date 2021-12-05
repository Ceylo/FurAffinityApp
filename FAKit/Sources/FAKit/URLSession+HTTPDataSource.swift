//
//  URLSession+HTTPDataSource.swift
//  
//
//  Created by Ceylo on 24/10/2021.
//

import Foundation

extension URLSession: HTTPDataSource {
    public func httpData(from url: URL, cookies: [HTTPCookie]?, completionHandler: @escaping (Data?) -> Void) {
        if let cookies = cookies {
            self.configuration.httpCookieStorage!
                .setCookies(cookies, for: url, mainDocumentURL: url)
        }
        print(#function, ":", url)
        
        self.dataTask(with: url) { data, response, error in
            guard error == nil else {
                completionHandler(nil)
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let mimeType = httpResponse.mimeType, mimeType == "text/html"
            else {
                completionHandler(nil)
                return
            }
            
            completionHandler(data)
        }
        .resume()
        
    }
}
