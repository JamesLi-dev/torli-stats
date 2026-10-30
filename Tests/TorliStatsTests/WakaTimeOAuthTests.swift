import XCTest
@testable import TorliStats

final class WakaTimeOAuthTests: XCTestCase {
    func testBearerHeaderForAllEndpointKindsDoesNotLeakTokenIntoURL() throws {
        for path in ["summaries?start=2026-10-30&end=2026-10-30", "summaries?start=2026-10-01&end=2026-10-30", "stats/last_30_days"] {
            let url = try XCTUnwrap(URL(string: "https://api.wakatime.com/api/v1/users/current/" + path))
            let request = WakaTimeUsageClient.authenticatedRequest(url: url, token: "test-oauth-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-oauth-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertEqual(request.url, url)
            XCTAssertFalse(request.url!.absoluteString.contains("test-oauth-token"))
            XCTAssertNil(request.httpBody)
        }
    }

    func testStatusErrorsAreConsistentEvenWithMissingResponseBody() throws {
        let url = try XCTUnwrap(URL(string: "https://api.wakatime.com/api/v1/users/current/summaries"))
        for (status, key) in [(401, "wakatime.error.invalid_token"), (403, "wakatime.error.forbidden"), (429, "wakatime.error.rate_limited")] {
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)
            for data in [nil, Data("server response must not leak tokens".utf8)] as [Data?] {
                XCTAssertThrowsError(try WakaTimeUsageClient.responseData(data, response: response)) { error in
                    XCTAssertEqual(error.localizedDescription, StatsL10n.text(key))
                }
            }
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        let body = Data("{\"data\":[]}".utf8)
        XCTAssertEqual(try WakaTimeUsageClient.responseData(body, response: response), body)
        XCTAssertThrowsError(try WakaTimeUsageClient.responseData(nil, response: response))
        XCTAssertThrowsError(try WakaTimeUsageClient.responseData(body, response: nil))
    }
}
