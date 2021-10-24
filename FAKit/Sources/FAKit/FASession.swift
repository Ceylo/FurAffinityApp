//
//  FASession.swift
//
//
//  Created by Ceylo on 24/10/2021.
//

import Foundation
import FAPages

struct FASession {
    init?(cookies: [HTTPCookie], dataSource: HTTPDataSource = URLSession.shared) async {
        guard let data = await dataSource.httpData(from: FAHomePage.url),
              let page = FAHomePage(data: data),
              page.username != nil
        else { return nil }
        
    }
}

