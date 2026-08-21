//
//  LoginCookies.swift
//  FurAffinity
//
//  Dropping the credentials the login web view established, so SettingsView doesn't
//  name a particular web stack. iOS is FALoginView (WebKit); Android re-declares this
//  function over its own WebView in Helpers/Android/LoginCookies+Android.swift.
//

#if !FA_SKIP_MODULE

import Foundation
import FAKit

func clearLoginCookies() async {
    await FALoginView.logout()
}

#endif
