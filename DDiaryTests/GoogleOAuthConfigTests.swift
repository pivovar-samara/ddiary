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
}
