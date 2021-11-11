//
//  FALoginView.swift
//  
//
//  Created by Ceylo on 24/10/2021.
//

import SwiftUI
import FAPages
import WebKit

public struct FALoginView: View {
    @Binding var session: FASession?
    @State private var cookies = [HTTPCookie]()
    
    public init(session: Binding<FASession?>) {
        self._session = session
    }
    
    public var body: some View {
        WebView(initialUrl: FAHomePage.url.appendingPathComponent("login"),
                cookies: $cookies,
                clearCookies: true)
            .onChange(of: cookies) { newCookies in
                Task {
                    session = await FASession(cookies: cookies)
                }
            }
    }
    
    public static func makeSession() async -> FASession? {
        let cookies = await WebView.defaultCookies()
        return await FASession(cookies: cookies)
    }
    
    public static func logout() async {
        await WebView.clearCookies()
    }
}

struct FALoginView_Previews: PreviewProvider {
    static var previews: some View {
        FALoginView(session: .constant(nil))
    }
}
