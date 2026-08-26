import Combine
import Foundation

final class CodexAccountsUsageStore: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()

    private let configurationsProvider: () -> [CodexAccountConfiguration]
    private var stores: [UUID: CodexUsageStore] = [:]
    private var storeCancellables: [UUID: AnyCancellable] = [:]

    init(configurationsProvider: @escaping () -> [CodexAccountConfiguration]) {
        self.configurationsProvider = configurationsProvider
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

    func synchronize() {
        let configurations = configurationsProvider()
        let activeIDs = Set(configurations.map(\.id))

        for id in Array(stores.keys) where !activeIDs.contains(id) {
            stores[id] = nil
            storeCancellables[id] = nil
        }

        for configuration in configurations where stores[configuration.id] == nil {
            let accountID = configuration.id
            let store = CodexUsageStore { [weak self] in
                self?.configurationsProvider()
                    .first(where: { $0.id == accountID })?
                    .homePath
            }
            stores[accountID] = store
            storeCancellables[accountID] = store.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        }
        objectWillChange.send()
    }
}
