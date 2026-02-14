import XCTest
import UIKit
@testable import DDiary

@MainActor
final class GoogleOAuthConfigTests: XCTestCase {
    func test_redirectScheme_defaultsToRedirectURIScheme() {
        let oldURI = GoogleOAuthConfig.redirectURI
        let oldOverride = GoogleOAuthConfig.callbackSchemeOverride
        defer {
            GoogleOAuthConfig.redirectURI = oldURI
            GoogleOAuthConfig.callbackSchemeOverride = oldOverride
        }

        GoogleOAuthConfig.callbackSchemeOverride = nil
        GoogleOAuthConfig.redirectURI = "com.example.app:/oauthredirect"

        XCTAssertEqual(GoogleOAuthConfig.redirectScheme, "com.example.app")
    }

    func test_redirectScheme_usesOverrideWhenProvided() {
        let oldURI = GoogleOAuthConfig.redirectURI
        let oldOverride = GoogleOAuthConfig.callbackSchemeOverride
        defer {
            GoogleOAuthConfig.redirectURI = oldURI
            GoogleOAuthConfig.callbackSchemeOverride = oldOverride
        }

        GoogleOAuthConfig.redirectURI = "com.example.app:/oauthredirect"
        GoogleOAuthConfig.callbackSchemeOverride = "custom-scheme"

        XCTAssertEqual(GoogleOAuthConfig.redirectScheme, "custom-scheme")
    }

    func test_redirectScheme_fallsBackWhenRedirectURIHasNoScheme() {
        let oldURI = GoogleOAuthConfig.redirectURI
        let oldOverride = GoogleOAuthConfig.callbackSchemeOverride
        defer {
            GoogleOAuthConfig.redirectURI = oldURI
            GoogleOAuthConfig.callbackSchemeOverride = oldOverride
        }

        GoogleOAuthConfig.callbackSchemeOverride = nil
        GoogleOAuthConfig.redirectURI = "://bad-uri"

        XCTAssertEqual(GoogleOAuthConfig.redirectScheme, "ddiary")
    }

    func test_presentationAnchor_returnsFallbackForEmptyScenes() {
        let anchor = GoogleOAuth.presentationAnchor(from: [])
        XCTAssertNotNil(anchor)
    }

    func test_googleOAuth_formURLEncoded_encodesSpecialCharactersStrictly() {
        let params = [
            "scope": "openid email profile",
            "grant_type": "refresh token",
            "client_id": "abc+123@example.com",
            "redirect_uri": "com.example.app:/oauthredirect?x=1&y=2",
            "unicode": "cafe~ and !"
        ]

        let encoded = GoogleOAuth.formURLEncoded(params)

        XCTAssertEqual(
            encoded,
            "client_id=abc%2B123%40example.com&grant_type=refresh+token&redirect_uri=com.example.app%3A%2Foauthredirect%3Fx%3D1%26y%3D2&scope=openid+email+profile&unicode=cafe%7E+and+%21"
        )
    }

    func test_googleSheetsClient_formURLEncoded_encodesSpecialCharactersStrictly() {
        let params = [
            "scope": "openid email profile",
            "grant_type": "refresh token",
            "client_id": "abc+123@example.com",
            "redirect_uri": "com.example.app:/oauthredirect?x=1&y=2",
            "unicode": "cafe~ and !"
        ]
        let client = LiveGoogleSheetsClient()

        let encoded = client.formURLEncoded(params)

        XCTAssertEqual(
            encoded,
            "client_id=abc%2B123%40example.com&grant_type=refresh+token&redirect_uri=com.example.app%3A%2Foauthredirect%3Fx%3D1%26y%3D2&scope=openid+email+profile&unicode=cafe%7E+and+%21"
        )
    }
}
