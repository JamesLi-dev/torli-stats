import AppKit
import Foundation

/// Evaluates the local quiet-hours schedule and wakes exactly at its next
/// boundary. It has no polling loop, so pausing monitoring also pauses the
/// scheduler's own recurring work.
final class MonitoringPauseController {
    private let settings: AppSettings
    private var boundaryTimer: DispatchSourceTimer?
    private var wakeObserver: NSObjectProtocol?

    private(set) var isPaused = false
    var onPauseStateChanged: ((Bool) -> Void)?

    init(settings: AppSettings) {
        self.settings = settings
        isPaused = Self.isPaused(
            at: Date(),
            isEnabled: settings.nightMonitoringPauseEnabled,
            startSeconds: settings.nightMonitoringPauseStartSeconds,
            endSeconds: settings.nightMonitoringPauseEndSeconds
        )
    }

    deinit {
        boundaryTimer?.cancel()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    func start() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.evaluate()
        }
        evaluate(notifyWhenUnchanged: false)
    }

    func updateSchedule() {
        evaluate()
    }

    private func evaluate(notifyWhenUnchanged: Bool = true) {
        let paused = Self.isPaused(
            at: Date(),
            isEnabled: settings.nightMonitoringPauseEnabled,
            startSeconds: settings.nightMonitoringPauseStartSeconds,
            endSeconds: settings.nightMonitoringPauseEndSeconds
        )
        let changed = paused != isPaused
        isPaused = paused
        installBoundaryTimer()
        if changed || notifyWhenUnchanged {
            onPauseStateChanged?(paused)
        }
    }

    private func installBoundaryTimer() {
        boundaryTimer?.cancel()
        boundaryTimer = nil
        guard settings.nightMonitoringPauseEnabled,
              settings.nightMonitoringPauseStartSeconds != settings.nightMonitoringPauseEndSeconds,
              let nextBoundary = Self.nextBoundary(
                after: Date(),
                startSeconds: settings.nightMonitoringPauseStartSeconds,
                endSeconds: settings.nightMonitoringPauseEndSeconds
              ) else { return }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + max(0.1, nextBoundary.timeIntervalSinceNow), leeway: .seconds(1))
        timer.setEventHandler { [weak self] in self?.evaluate() }
        timer.resume()
        boundaryTimer = timer
    }

    private static func isPaused(
        at date: Date,
        isEnabled: Bool,
        startSeconds: Int,
        endSeconds: Int
    ) -> Bool {
        guard isEnabled, startSeconds != endSeconds else { return false }
        let calendar = Calendar.autoupdatingCurrent
        let seconds = calendar.component(.hour, from: date) * 3_600
            + calendar.component(.minute, from: date) * 60
            + calendar.component(.second, from: date)
        if startSeconds < endSeconds {
            return seconds >= startSeconds && seconds < endSeconds
        }
        return seconds >= startSeconds || seconds < endSeconds
    }

    private static func nextBoundary(after date: Date, startSeconds: Int, endSeconds: Int) -> Date? {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: date)
        let candidates = [startSeconds, endSeconds].compactMap { seconds -> Date? in
            guard let todayBoundary = calendar.date(byAdding: .second, value: seconds, to: today) else { return nil }
            if todayBoundary > date { return todayBoundary }
            return calendar.date(byAdding: .day, value: 1, to: todayBoundary)
        }
        return candidates.min()
    }
}
