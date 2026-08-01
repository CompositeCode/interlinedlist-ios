import XCTest
@testable import InterlinedList

final class AppDeepLinkParseTests: XCTestCase {

    private func parse(_ string: String) -> AppDeepLink? {
        guard let url = URL(string: string) else { return nil }
        return AppDeepLink.parse(url)
    }

    // MARK: Custom scheme — content

    func test_parse_customSchemeUserHost_returnsUserProfile() {
        XCTAssertEqual(parse("interlinedlist://user/bob"), .userProfile(username: "bob"))
    }

    func test_parse_customSchemeMessageHost_returnsMessage() {
        XCTAssertEqual(parse("interlinedlist://message/abc"), .message(id: "abc"))
    }

    func test_parse_customSchemeUserAsFirstPathSegment_returnsUserProfile() {
        // interlinedlist:///user/bob puts the target in the first path segment (empty host).
        XCTAssertEqual(parse("interlinedlist:///user/bob"), .userProfile(username: "bob"))
    }

    // MARK: Web permalinks — content

    func test_parse_httpsCanonicalUser_returnsUserProfile() {
        XCTAssertEqual(parse("https://interlinedlist.com/user/bob"), .userProfile(username: "bob"))
    }

    func test_parse_httpsWwwMessage_returnsMessage() {
        XCTAssertEqual(parse("https://www.interlinedlist.com/message/abc"), .message(id: "abc"))
    }

    func test_parse_httpsCanonicalList_isNotRouted_returnsNil() {
        // Inbound list/document deep links are out of scope this pass.
        XCTAssertNil(parse("https://interlinedlist.com/lists/xyz"))
    }

    // MARK: Rejections

    func test_parse_httpsForeignHost_returnsNil() {
        XCTAssertNil(parse("https://evil.example.com/user/bob"))
    }

    func test_parse_httpsInterlinedlistUnknownTarget_returnsNil() {
        XCTAssertNil(parse("https://interlinedlist.com/dashboard"))
    }

    func test_parse_customSchemeUnknownTarget_returnsNil() {
        XCTAssertNil(parse("interlinedlist://settings/foo"))
    }

    func test_parse_customSchemeUserMissingUsername_returnsNil() {
        XCTAssertNil(parse("interlinedlist://user"))
    }

    func test_parse_otherScheme_returnsNil() {
        XCTAssertNil(parse("mailto:someone@example.com"))
    }

    // MARK: Auth deep links still recognized

    func test_parse_resetPassword_returnsResetPasswordWithToken() {
        XCTAssertEqual(parse("interlinedlist://reset-password?token=abc123"),
                       .resetPassword(token: "abc123"))
    }

    func test_parse_verifyEmail_returnsVerifyEmailWithToken() {
        XCTAssertEqual(parse("interlinedlist://verify-email?token=tok"),
                       .verifyEmail(token: "tok"))
    }

    func test_parse_verifyEmailChange_returnsVerifyEmailChangeWithToken() {
        XCTAssertEqual(parse("interlinedlist://verify-email-change?token=tok"),
                       .verifyEmailChange(token: "tok"))
    }

    func test_parse_resetPasswordMissingToken_returnsNil() {
        XCTAssertNil(parse("interlinedlist://reset-password"))
    }

    func test_parse_httpsResetPassword_returnsResetPassword() {
        XCTAssertEqual(parse("https://interlinedlist.com/reset-password?token=xyz"),
                       .resetPassword(token: "xyz"))
    }
}
