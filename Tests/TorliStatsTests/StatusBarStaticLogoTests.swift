import AppKit
import XCTest
@testable import TorliStats

final class StatusBarStaticLogoTests: XCTestCase {
    func testEveryStaticLogoHasRenderableTemplateArtwork() throws {
        for logo in StatusBarStaticLogo.allCases {
            let image = try XCTUnwrap(logo.makeImage(), "Missing symbol for \(logo.rawValue)")
            XCTAssertTrue(image.isTemplate)
            XCTAssertGreaterThan(image.size.width, 0)
            XCTAssertGreaterThan(image.size.height, 0)
            XCTAssertNotNil(image.tiffRepresentation, "Cannot render \(logo.rawValue)")
        }
    }
    func testApprovedArtworkRetainsTransparencyAndIsCached() throws {
        for logo in [StatusBarStaticLogo.orbit, .link, .pinwheel, .meters, .prism] {
            let image = try XCTUnwrap(logo.makeImage())
            XCTAssertTrue(image === logo.makeImage())
            XCTAssertEqual(max(image.size.width, image.size.height), 18, accuracy: 0.01)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
            var transparent = 0
            var opaque = 0
            for row in 0..<16 {
                for column in 0..<16 {
                    let alpha = try XCTUnwrap(bitmap.colorAt(
                        x: column * (bitmap.pixelsWide - 1) / 15,
                        y: row * (bitmap.pixelsHigh - 1) / 15
                    )).alphaComponent
                    if alpha < 0.05 { transparent += 1 }
                    if alpha > 0.9 { opaque += 1 }
                }
            }
            XCTAssertGreaterThan(transparent, 20, "Artwork must not be an opaque rectangle")
            XCTAssertGreaterThan(opaque, 20, "Artwork must not be blank")
        }
    }

    func testReplacedSelectionsMigrateAndRetainedSelectionsStaySelected() {
        XCTAssertEqual(StatusBarStaticLogo(savedValue: "torli"), .orbit)
        XCTAssertEqual(StatusBarStaticLogo(savedValue: "cat"), .link)
        XCTAssertEqual(StatusBarStaticLogo(savedValue: "mountain"), .prism)
        XCTAssertEqual(StatusBarStaticLogo(savedValue: "pulse"), .pulse)
        XCTAssertEqual(StatusBarStaticLogo(savedValue: "leaf"), .leaf)
        XCTAssertEqual(StatusBarStaticLogo(savedValue: "sparkles"), .sparkles)
        XCTAssertEqual(StatusBarStaticLogo(savedValue: "unknown"), .orbit)
    }
}
