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
    var onError: (Error) -> Void
    @State private var cookies = [HTTPCookie]()
    
    static private let cookieCache: Storage<Int, [CodableHTTPCookie]> = try! Storage(
        diskConfig: DiskConfig(name: "SessionCookies"),
        memoryConfig: MemoryConfig(),
        fileManager: .default,
        transformer: TransformerFactory.forCodable(ofType: [CodableHTTPCookie].self)
    )
    
    public init(session: Binding<OnlineFASession?>, onError: @escaping (Error) -> Void) {
        self._session = session
        self.onError = onError
    }
    
    public var body: some View {
        WebView(initialUrl: FAURLs.homeUrl.appendingPathComponent("login"),
                cookies: $cookies,
                clearCookies: true)
            .onChange(of: cookies) { _, newCookies in
                Task {
                    guard session == nil else { return }
                    do {
                        session = try await Self.makeSession(cookies: newCookies)
                    } catch {
                        onError(error)
                    }
                }
            }
    }
    
    public static func makeSession(cookies: [HTTPCookie]? = nil) async throws -> OnlineFASession? {
        let rawCookies: [HTTPCookie]
        if let cookies {
            rawCookies = cookies
        } else {
            if let cookies = try? cookieCache.object(forKey: 0) {
                rawCookies = cookies
            } else {
                rawCookies = await WebView.defaultCookies()
            }
        }

        // CloudFlare cookies are transport-layer state: they live in
        // HTTPCookieStorage.shared so they can be refreshed by FAChallengeView
        // without OnlineFASession's stored auth cookies clobbering them on
        // every request.
        for cookie in rawCookies where cookie.name == "cf_clearance" {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
        let authCookies = rawCookies.filter { $0.name != "cf_clearance" }

        let session = try await OnlineFASession(cookies: authCookies)
        if session != nil {
            let codableCookies = rawCookies.map { CodableHTTPCookie($0)! }
            try! cookieCache.setObject(codableCookies, forKey: 0)
        }

        return session
    }
    
    public static func logout() async {
        await WebView.clearCookies()
        try! cookieCache.removeAll()
        
        let newSession = try? await makeSession()
        assert(newSession == nil)
    }
}

#Preview {
    FALoginView(session: .constant(nil), onError: { _ in })
}
