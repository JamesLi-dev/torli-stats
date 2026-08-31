import Combine
import Foundation

final class CodexAccountsUsageStore: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()

    private let configurationsProvider: () -> [CodexAccountConfiguration]
    private let refreshSettingsProvider: () -> CodexRefreshSettings
    private var stores: [UUID: CodexUsageStore] = [:]
    private var storeCancellables: [UUID: AnyCancellable] = [:]

    init(
        configurationsProvider: @escaping () -> [CodexAccountConfiguration],
        refreshSettingsProvider: @escaping () -> CodexRefreshSettings
    ) {
        self.configurationsProvider = configurationsProvider
        self.refreshSettingsProvider = refreshSettingsProvider
        synchronize()
    }

    var accounts: [CodexAccountConfiguration] {
        configurationsProvider()
    }

    var defaultState: CodexUsageState {
        state(for: CodexAccountConfiguration.defaultAccountID)
    }

    func state(for accountID: UUID) -> CodexUsageState {
        stores[accountID]?.state ?? .idle
    }

    func refresh() {
        synchronize()
        stores.values.forEach { $0.refresh() }
    }

    func refresh(accountID: UUID) {
        synchronize()
        stores[accountID]?.refresh()
    }

    func lastSuccessfulRefresh(for accountID: UUID) -> Date? {
        state(for: accountID).snapshot?.fetchedAt
    }

    func testConnection(
        for account: CodexAccountConfiguration,
        completion: @escaping (Result<CodexUsageSnapshot, CodexUsageError>) -> Void
    ) {
        CodexUsageClient(homePathProvider: { account.homePath }).fetch(completion: completion)
    }

    func synchronize() {
        let configurations = configurationsProvider()
        // Do not launch a Codex app-server for accounts that are not shown
        // anywhere. Hidden accounts can be enabled later and will be created
        // lazily on the next synchronization.
        let activeIDs = Set(configurations
            .filter { $0.isDashboardVisible || $0.isStatusBarIncluded }
            .map(\.id))

        for id in Array(stores.keys) where !activeIDs.contains(id) {
            stores[id] = nil
            storeCancellables[id] = nil
        }

        let refreshSettings = refreshSettingsProvider()
        for configuration in configurations where activeIDs.contains(configuration.id) && stores[configuration.id] == nil {
            let accountID = configuration.id
            let store = CodexUsageStore(
                homePathProvider: { [weak self] in
                    self?.configurationsProvider()
                        .first(where: { $0.id == accountID })?
                        .homePath
                },
                refreshSettings: refreshSettings
            )
            stores[accountID] = store
            storeCancellables[accountID] = store.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        }
        stores.values.forEach { $0.setRefreshSettings(refreshSettings) }
        objectWillChange.send()
    }
}
