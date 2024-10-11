//
//  FALoginView.swift
//  
//
//  Created by Ceylo on 24/10/2021.
//

import SwiftUI
import FAPages
import WebKit
import Cache

public struct FALoginView: View {
    @Binding var session: OnlineFASession?
    @State private var cookies = [HTTPCookie]()
    
    static private let cookieCache: Storage<Int, [CodableHTTPCookie]> = try! Storage(
        diskConfig: DiskConfig(name: "SessionCookies"),
        memoryConfig: MemoryConfig(),
        fileManager: .default,
        transformer: TransformerFactory.forCodable(ofType: [CodableHTTPCookie].self)
    )
    
    public init(session: Binding<OnlineFASession?>) {
        self._session = session
    }
    
    public var body: some View {
        WebView(initialUrl: FAURLs.homeUrl.appendingPathComponent("login"),
                cookies: $cookies,
                clearCookies: true)
            .onChange(of: cookies) { _, newCookies in
                Task {
                    guard session == nil else { return }
                    session = await Self.makeSession(cookies: newCookies)
                }
            }
    }
    
    public static func makeSession(cookies: [HTTPCookie]? = nil) async -> OnlineFASession? {
        let actualCookies: [HTTPCookie]
        if let cookies {
            actualCookies = cookies
        } else {
            if let cookies = try? cookieCache.object(forKey: 0) {
                actualCookies = cookies
            } else {
                actualCookies = await WebView.defaultCookies()
            }
        }
        
        let session = await OnlineFASession(cookies: actualCookies)
        if session != nil {
            let codableCookies = actualCookies.map { CodableHTTPCookie($0)! }
            try! cookieCache.setObject(codableCookies, forKey: 0)
        }
        
        return session
    }
    
    public static func logout() async {
        await WebView.clearCookies()
        try! cookieCache.removeAll()
    }
}

struct FALoginView_Previews: PreviewProvider {
    static var previews: some View {
        FALoginView(session: .constant(nil))
    }
}
