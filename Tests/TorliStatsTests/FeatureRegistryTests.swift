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
        XCTAssertEqual(DashboardTab.available.map(\.id), ["monitoring", "statistics"])
        XCTAssertEqual(DashboardModule.allCases.filter { $0.dashboardTabID == "statistics" }, [.codex, .wakatime])
        XCTAssertEqual(DashboardModule.allCases.filter { $0.dashboardTabID == "monitoring" }.count, 10)
    }

    @MainActor
    func testGroupedFeaturesShareTabAndRestoreOldSelection() {
        let first = SampleFeature(), second = SampleFeature()
        second.id = "other"
        FeatureRegistry.shared.register([first, second])
        defer { FeatureRegistry.shared.register([]) }
        XCTAssertEqual(DashboardTab.available.map(\.id), ["monitoring", "statistics", "feature:sample"])
        XCTAssertEqual(DashboardModule.feature("other").dashboardTabID, "feature:sample")
        XCTAssertEqual(DashboardTab.resolvedID("feature:other"), "feature:sample")
        first.isEnabled = false; first.showsDashboardTabWhenDisabled = false
        XCTAssertEqual(DashboardTab.available.last?.id, "feature:sample")
        second.isEnabled = false; second.showsDashboardTabWhenDisabled = false
        XCTAssertEqual(DashboardTab.available.count, 2)
        XCTAssertEqual(DashboardTab.resolvedID("feature:other"), "monitoring")
    }

    @MainActor
    func testFeatureMayHideItsTabWhileDisabled() {
        let feature = SampleFeature(); feature.isEnabled = false; feature.showsDashboardTabWhenDisabled = false
        FeatureRegistry.shared.register([feature]); defer { FeatureRegistry.shared.register([]) }
        XCTAssertFalse(DashboardTab.available.map(\.id).contains("feature:sample"))
        XCTAssertTrue(SettingsCategory.allCases.contains(.feature("sample")))
        feature.isEnabled = true
        XCTAssertTrue(DashboardTab.available.map(\.id).contains("feature:sample"))
        feature.isEnabled = false; feature.showsDashboardTabWhenDisabled = true
        XCTAssertTrue(DashboardTab.available.map(\.id).contains("feature:sample"))
    }

    @MainActor
    func testRegisteredFeatureParticipatesInOrderNavigationAndLifecycle() throws {
        let feature = SampleFeature()
        FeatureRegistry.shared.register([feature])
        defer { FeatureRegistry.shared.register([]) }
        let module = try XCTUnwrap(DashboardModule(rawValue: "feature:sample"))
        XCTAssertEqual(module.title, "Sample")
        XCTAssertEqual(module.dashboardTabID, "feature:sample")
        XCTAssertEqual(DashboardTab.available.map(\.id), ["monitoring", "statistics", "feature:sample"])
        XCTAssertEqual(DashboardTab.available.last?.title, "Sample")
        XCTAssertFalse(module.isMetric)
        XCTAssertEqual(DashboardModule(rawValue: "sample"), module, "Legacy IDs migrate")
        XCTAssertEqual(try JSONDecoder().decode(DashboardModule.self, from: JSONEncoder().encode(module)), module)
        XCTAssertTrue(DashboardModule.allCases.contains(module))
        XCTAssertTrue(SettingsCategory.allCases.contains(.feature("sample")))
        XCTAssertEqual(SettingsCategory.feature("sample").title, "Sample")
        FeatureRegistry.shared.reset()
        FeatureRegistry.shared.dashboardDidClose()
        FeatureRegistry.shared.shutdown()
        XCTAssertEqual(feature.resets, 1)
        XCTAssertEqual(feature.dashboardCloses, 1)
        XCTAssertEqual(feature.stops, 1)
    }
}

private final class SampleFeature: TorliFeature {
    var id = "sample"
    var dashboardTabID = "feature:sample"
    let title = "Sample"
    let systemImage = "star"
    var changes: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }
    var isEnabled = true
    var showsDashboardTabWhenDisabled = true
    var canEnable = true
    var estimatedHeight: CGFloat = 100
    var resets = 0
    var stops = 0
    var dashboardCloses = 0
    func setEnabled(_ enabled: Bool) { isEnabled = enabled }
    func settingsView() -> AnyView { AnyView(EmptyView()) }
    func dashboardView(privacyMode: Bool, openSettings: @escaping () -> Void) -> AnyView { AnyView(EmptyView()) }
    func reset() { resets += 1 }
    func dashboardDidClose() { dashboardCloses += 1 }
    func shutdown() { stops += 1 }
}
