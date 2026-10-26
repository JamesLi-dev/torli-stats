import XCTest
import SwiftUI
import Combine
@testable import TorliStats

final class FeatureRegistryTests: XCTestCase {
    @MainActor
    func testCommunityHasNoExtensionPagesAndUnknownIDsAreRejected() {
        FeatureRegistry.shared.register([])
        XCTAssertNil(DashboardModule(rawValue: "feature:sample"))
        XCTAssertFalse(SettingsCategory.allCases.contains(.feature("sample")))
        XCTAssertEqual(DashboardModule.allCases.count, 12)
    }

    @MainActor
    func testRegisteredFeatureParticipatesInOrderNavigationAndLifecycle() throws {
        let feature = SampleFeature()
        FeatureRegistry.shared.register([feature])
        defer { FeatureRegistry.shared.register([]) }
        let module = try XCTUnwrap(DashboardModule(rawValue: "feature:sample"))
        XCTAssertEqual(module.title, "Sample")
        XCTAssertFalse(module.isMetric)
        XCTAssertEqual(DashboardModule(rawValue: "sample"), module, "Legacy IDs migrate")
        XCTAssertEqual(try JSONDecoder().decode(DashboardModule.self, from: JSONEncoder().encode(module)), module)
        XCTAssertTrue(DashboardModule.allCases.contains(module))
        XCTAssertTrue(SettingsCategory.allCases.contains(.feature("sample")))
        XCTAssertEqual(SettingsCategory.feature("sample").title, "Sample")
        FeatureRegistry.shared.reset()
        FeatureRegistry.shared.shutdown()
        XCTAssertEqual(feature.resets, 1)
        XCTAssertEqual(feature.stops, 1)
    }
}

private final class SampleFeature: TorliFeature {
    let id = "sample"
    let title = "Sample"
    let systemImage = "star"
    var changes: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }
    var isEnabled = true
    var canEnable = true
    var estimatedHeight: CGFloat = 100
    var resets = 0
    var stops = 0
    func setEnabled(_ enabled: Bool) { isEnabled = enabled }
    func settingsView() -> AnyView { AnyView(EmptyView()) }
    func dashboardView(privacyMode: Bool, openSettings: @escaping () -> Void) -> AnyView { AnyView(EmptyView()) }
    func reset() { resets += 1 }
    func shutdown() { stops += 1 }
}
