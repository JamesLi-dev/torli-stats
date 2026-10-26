import Combine
import SwiftUI

/// Extensions are registered by the application entry point before settings load.
/// Community builds have an empty registry and need no private dependencies.
public protocol TorliFeature: AnyObject {
    var id: String { get }
    var title: String { get }
    var systemImage: String { get }
    var changes: AnyPublisher<Void, Never> { get }
    var isEnabled: Bool { get }
    var canEnable: Bool { get }
    var estimatedHeight: CGFloat { get }
    func setEnabled(_ enabled: Bool)
    func settingsView() -> AnyView
    func dashboardView(privacyMode: Bool, openSettings: @escaping () -> Void) -> AnyView
    func reset()
    func shutdown()
}

public protocol TorliStatisticsProvider {
    func details(tab: StatisticsDetailTab, typing: TypingStatsService, development: WakaTimeUsageStore) -> AnyView
    func typingTrend(records: [TypingDailyRecord]) -> AnyView
    func developmentSummary(store: WakaTimeUsageStore) -> AnyView
}

final class FeatureRegistry: ObservableObject {
    static let shared = FeatureRegistry()
    var statistics: (any TorliStatisticsProvider)?
    private(set) var features: [any TorliFeature] = []
    private var subscriptions = Set<AnyCancellable>()

    func register(_ features: [any TorliFeature]) {
        precondition(Set(features.map(\.id)).count == features.count, "Duplicate feature IDs")
        precondition(features.allSatisfy { !$0.id.isEmpty && !$0.id.contains(":") }, "Invalid feature ID")
        self.features = features
        subscriptions.removeAll()
        for feature in features {
            feature.changes.receive(on: RunLoop.main).sink { [weak self] in
                self?.objectWillChange.send()
            }.store(in: &subscriptions)
        }
    }

    func feature(_ id: String) -> (any TorliFeature)? { features.first { $0.id == id } }
    func reset() { features.forEach { $0.reset() } }
    func shutdown() { features.forEach { $0.shutdown() } }
}

public enum TorliApplication {
    public static func run(features: [any TorliFeature] = [], statistics: (any TorliStatisticsProvider)? = nil) {
        FeatureRegistry.shared.statistics = statistics
        FeatureRegistry.shared.register(features)
        TorliStatsApp.main()
    }
}
