import Combine
import Foundation

final class CodexUsageStore: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()

    private(set) var state: CodexUsageState = .idle
    private let client: CodexUsageClient
    private var refreshTimer: DispatchSourceTimer?
    private var refreshInFlight = false
    private var refreshSettings: CodexRefreshSettings

    init(
        homePathProvider: @escaping () -> String?,
        refreshSettings: CodexRefreshSettings
    ) {
        client = CodexUsageClient(homePathProvider: homePathProvider)
        self.refreshSettings = refreshSettings
        installRefreshTimer()
        DispatchQueue.main.async { [weak self] in
            self?.refresh()
        }
    }

    deinit {
        refreshTimer?.cancel()
    }

    func refresh() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !refreshInFlight else { return }
        refreshInFlight = true
        state = .loading(state.snapshot)
        objectWillChange.send()

        client.fetch { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshInFlight = false
                switch result {
                case let .success(snapshot):
                    self.state = .available(snapshot)
                case let .failure(error):
                    self.state = .unavailable(error, self.state.snapshot)
                }
                self.objectWillChange.send()
            }
        }
    }

    func setRefreshSettings(_ settings: CodexRefreshSettings) {
        guard refreshSettings != settings else { return }
        refreshSettings = settings
        refreshTimer?.cancel()
        refreshTimer = nil
        installRefreshTimer()
    }

    private func installRefreshTimer() {
        guard refreshSettings.isEnabled else { return }
        let seconds = max(1, refreshSettings.intervalMinutes) * 60
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .seconds(seconds), repeating: .seconds(seconds), leeway: .seconds(5))
        timer.setEventHandler { [weak self] in
            self?.refresh()
        }
        timer.resume()
        refreshTimer = timer
    }
}
