import Combine
import Foundation

final class CodexUsageStore: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()

    private(set) var state: CodexUsageState = .idle
    private let client: CodexUsageClient
    private var refreshTimer: DispatchSourceTimer?
    private var retryTimer: DispatchSourceTimer?
    private var activeRequest: CodexUsageRequest?
    private var refreshInFlight = false
    private var retryAttempt = 0
    private var refreshSettings: CodexRefreshSettings

    private static let maximumRetryAttempts = 2

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
        retryTimer?.cancel()
        activeRequest?.cancel()
    }

    func refresh() {
        dispatchPrecondition(condition: .onQueue(.main))
        cancelPendingRetry()
        retryAttempt = 0
        startRefresh()
    }

    private func startRefresh() {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        state = .loading(state.snapshot)
        objectWillChange.send()

        activeRequest = client.fetch { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.activeRequest = nil
                self.refreshInFlight = false
                switch result {
                case let .success(snapshot):
                    self.retryAttempt = 0
                    self.state = .available(snapshot)
                case let .failure(error):
                    self.handleRefreshFailure(error)
                }
                self.objectWillChange.send()
            }
        }
    }

    private func handleRefreshFailure(_ error: CodexUsageError) {
        guard error.isRetryable, retryAttempt < Self.maximumRetryAttempts else {
            state = .unavailable(error, state.snapshot)
            return
        }

        retryAttempt += 1
        let delay: TimeInterval = retryAttempt == 1 ? 3 : 10
        let retryAt = Date().addingTimeInterval(delay)
        state = .retrying(error, state.snapshot, attempt: retryAttempt, retryAt: retryAt)

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + delay)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.retryTimer?.cancel()
            self.retryTimer = nil
            self.startRefresh()
        }
        timer.resume()
        retryTimer = timer
    }

    private func cancelPendingRetry() {
        retryTimer?.cancel()
        retryTimer = nil
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
