import XCTest
import UIKit
@testable import DDiary

@MainActor
final class GoogleOAuthConfigTests: XCTestCase {
    func test_defaultScope_requestsDriveFileOnly() {
        XCTAssertEqual(GoogleOAuthConfig.scope, GoogleOAuthConfig.driveFileScope)
        XCTAssertEqual(GoogleOAuthConfig.requiredScopes, [GoogleOAuthConfig.driveFileScope])
    }

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

    // MARK: - Presentation anchor resolution

    func test_resolvePresentationAnchor_emptyScenes_returnsNil() {
        let anchor = GoogleOAuth.resolvePresentationAnchor(from: [])
        XCTAssertNil(anchor, "Empty scene set should return nil, not crash or block")
    }

    func test_resolvePresentationAnchor_noScenes_doesNotCrashOrBlock() {
        // Verifies the old preconditionFailure / busy-wait path is gone.
        // With no scenes the method must return nil immediately.
        let start = Date()
        let anchor = GoogleOAuth.resolvePresentationAnchor(from: [])
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertNil(anchor)
        XCTAssertLessThan(elapsed, 0.5, "resolvePresentationAnchor should return immediately, not busy-wait")
    }

    func test_noPresentationAnchor_errorHasLocalizedDescription() {
        let error = GoogleOAuth.OAuthError.noPresentationAnchor
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("window") == true)
    }

    func test_resolvePresentationAnchor_returnsAnchorFromConnectedScenes() {
        // When the test host app has connected scenes, verify a non-nil anchor.
        let scenes = UIApplication.shared.connectedScenes
        guard !scenes.isEmpty else { return } // Skip when no scenes (e.g., headless CI)
        let anchor = GoogleOAuth.resolvePresentationAnchor(from: scenes)
        XCTAssertNotNil(anchor, "Should resolve anchor from the test host's connected scenes")
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

    func test_googleOAuth_formURLEncoded_handlesUnicodeControlAndEmptyEdgeCases() {
        let params = [
            "line": "a\nb\tc",
            "emoji": "A🙂",
            "reserved": "%+ ~*",
            "empty": ""
        ]

        let encoded = GoogleOAuth.formURLEncoded(params)

        XCTAssertEqual(
            encoded,
            "emoji=A%F0%9F%99%82&empty=&line=a%0Ab%09c&reserved=%25%2B+%7E*"
        )
    }

    func test_googleSheetsClient_formURLEncoded_handlesUnicodeControlAndEmptyEdgeCases() {
        let params = [
            "line": "a\nb\tc",
            "emoji": "A🙂",
            "reserved": "%+ ~*",
            "empty": ""
        ]
        let client = LiveGoogleSheetsClient()

        let encoded = client.formURLEncoded(params)

        XCTAssertEqual(
            encoded,
            "emoji=A%F0%9F%99%82&empty=&line=a%0Ab%09c&reserved=%25%2B+%7E*"
        )
    }

    func test_parseAuthorizationCallback_returnsCodeForValidState() throws {
        let callbackURL = try XCTUnwrap(URL(string: "com.example.app:/oauthredirect?state=expected-state&code=auth-code"))
        let code = try GoogleOAuth.parseAuthorizationCallback(callbackURL, expectedState: "expected-state")
        XCTAssertEqual(code, "auth-code")
    }

    func test_parseAuthorizationCallback_throwsInvalidStateOnMismatch() throws {
        let callbackURL = try XCTUnwrap(URL(string: "com.example.app:/oauthredirect?state=wrong&code=auth-code"))

        XCTAssertThrowsError(try GoogleOAuth.parseAuthorizationCallback(callbackURL, expectedState: "expected-state")) { error in
            guard case GoogleOAuth.OAuthError.invalidState = error else {
                return XCTFail("Expected invalidState, got \(error)")
            }
        }
    }

    func test_parseAuthorizationCallback_throwsAuthorizationFailedWhenOAuthReturnsError() throws {
        let callbackURL = try XCTUnwrap(
            URL(string: "com.example.app:/oauthredirect?state=expected-state&error=invalid_request&error_description=Incremental+authorization+not+supported")
        )

        XCTAssertThrowsError(try GoogleOAuth.parseAuthorizationCallback(callbackURL, expectedState: "expected-state")) { error in
            guard case let GoogleOAuth.OAuthError.authorizationFailed(code, description) = error else {
                return XCTFail("Expected authorizationFailed, got \(error)")
            }
            XCTAssertEqual(code, "invalid_request")
            XCTAssertEqual(description, "Incremental authorization not supported")
        }
    }
}
