import Combine
import Foundation

final class CodexUsageStore: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()

    private(set) var state: CodexUsageState = .idle
    private let client: CodexUsageClient
    private var refreshTimer: DispatchSourceTimer?
    private var refreshInFlight = false

    init(homePathProvider: @escaping () -> String?) {
        client = CodexUsageClient(homePathProvider: homePathProvider)
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

    private func installRefreshTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 300, repeating: 300, leeway: .seconds(5))
        timer.setEventHandler { [weak self] in
            self?.refresh()
        }
        timer.resume()
        refreshTimer = timer
    }
}
