import Foundation
import XCTest
@testable import TorliStats

final class UpdateReleaseNotesTests: XCTestCase {
    private func release(_ version: String, _ url: String) -> AppUpdateRelease {
        AppUpdateRelease(version: version, downloadURL: URL(string: url)!, publishedAt: nil)
    }

    func testNotesOnlyLoadFromMatchingOfficialRelease() {
        let official = release("1.13.0", "https://github.com/JamesLi-dev/torli-stats/releases/tag/v1.13.0")
        XCTAssertEqual(AppUpdateReleaseNotes.requestURL(for: official)?.absoluteString,
                       "https://api.github.com/repos/JamesLi-dev/torli-stats/releases/tags/v1.13.0")
        XCTAssertNil(AppUpdateReleaseNotes.requestURL(for: release("1.13.1", official.downloadURL.absoluteString)))
        XCTAssertNil(AppUpdateReleaseNotes.requestURL(for: release("1.13.0", "https://example.com/JamesLi-dev/torli-stats/releases/tag/v1.13.0")))
        XCTAssertNil(AppUpdateReleaseNotes.requestURL(for: release("1.13.0", "https://github.com/other/torli-stats/releases/tag/v1.13.0")))
        XCTAssertNil(AppUpdateReleaseNotes.requestURL(for: release("1.13.0", "https://github.com/JamesLi-dev/torli-stats/releases/tag/v1.13.0?redirect=1")))
    }

    func testNotesParsingRejectsWrongTagMissingBodyAndOversizedResponse() throws {
        let data = try JSONSerialization.data(withJSONObject: ["tag_name": "v1.13.0", "body": "### 中文\n- 新功能\n### English\n- Feature"])
        XCTAssertEqual(AppUpdateReleaseNotes.parse(data, expectedTag: "v1.13.0"), "### 中文\n- 新功能\n### English\n- Feature")
        XCTAssertNil(AppUpdateReleaseNotes.parse(data, expectedTag: "v1.12.6"))
        let missing = try JSONSerialization.data(withJSONObject: ["tag_name": "v1.13.0"])
        XCTAssertNil(AppUpdateReleaseNotes.parse(missing, expectedTag: "v1.13.0"))
        let empty = try JSONSerialization.data(withJSONObject: ["tag_name": "v1.13.0", "body": NSNull()])
        XCTAssertEqual(AppUpdateReleaseNotes.parse(empty, expectedTag: "v1.13.0"), "")
        XCTAssertNil(AppUpdateReleaseNotes.parse(Data(repeating: 65, count: AppUpdateReleaseNotes.maximumResponseBytes + 1), expectedTag: "v1.13.0"))
    }
}
