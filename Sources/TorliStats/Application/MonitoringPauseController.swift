import AppKit
import Foundation

/// The current automatic sampling policy. Manual refreshes remain available in
/// every state; only recurring background work is affected.
enum MonitoringSamplingMode: Equatable {
    case realtime
    case lowFrequency
    case paused(MonitoringPauseReason)

    var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }
}

enum MonitoringPauseReason: Equatable {
    case manual
    case dashboardClosed
    case nightSchedule
    case systemSleep
    case displaySleep
    case screenLocked

    var dashboardMessage: String {
        switch self {
        case .manual: return StatsL10n.text("monitoring.pause_reason.manual")
        case .dashboardClosed: return StatsL10n.text("monitoring.pause_reason.dashboard_closed")
        case .nightSchedule: return StatsL10n.text("monitoring.pause_reason.night")
        case .systemSleep: return StatsL10n.text("monitoring.pause_reason.system_sleep")
        case .displaySleep: return StatsL10n.text("monitoring.pause_reason.display_sleep")
        case .screenLocked: return StatsL10n.text("monitoring.pause_reason.screen_locked")
        }
    }
}

/// Chooses one sampling policy from the quiet-hours schedule, system display
/// lifecycle, Dashboard visibility, and a permission-free system idle clock.
/// It schedules only its next time boundary and a lightweight 60-second idle
/// check; it never collects metrics itself.
final class MonitoringPauseController {
    private static let idleThreshold: TimeInterval = 25 * 60

    private let settings: AppSettings
    private var boundaryTimer: DispatchSourceTimer?
    private var idleTimer: DispatchSourceTimer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var dashboardVisible = false
    private var systemSleeping = false
    private var displaySleeping = false
    private var screenLocked = false

    private(set) var mode: MonitoringSamplingMode
    var isPaused: Bool { mode.isPaused }
    var onSamplingModeChanged: ((MonitoringSamplingMode) -> Void)?

    init(settings: AppSettings) {
        self.settings = settings
        if settings.manualMonitoringPaused {
            mode = .paused(.manual)
        } else if Self.nightScheduleIsActive(
            at: Date(),
            isEnabled: settings.nightMonitoringPauseEnabled,
            startSeconds: settings.nightMonitoringPauseStartSeconds,
            endSeconds: settings.nightMonitoringPauseEndSeconds
        ) {
            mode = .paused(.nightSchedule)
        } else if !settings.backgroundMonitoringEnabled {
            mode = .paused(.dashboardClosed)
        } else {
            mode = .realtime
        }
    }

    deinit {
        boundaryTimer?.cancel()
        idleTimer?.cancel()
        observers.forEach { center, observer in center.removeObserver(observer) }
    }

    func start() {
        observeWorkspaceLifecycle()
        observeScreenLockLifecycle()
        evaluate(reconfigureTimers: true)
    }

    func updateSchedule() {
        evaluate(reconfigureTimers: true)
    }

    func updateManualPause() {
        evaluate(reconfigureTimers: true)
    }

    func updateBackgroundMonitoring() {
        evaluate(reconfigureTimers: true)
    }

    func setDashboardVisible(_ visible: Bool) {
        guard dashboardVisible != visible else { return }
        dashboardVisible = visible
        evaluate(reconfigureTimers: true)
    }

    /// Lets explicit actions (for example a menu refresh) leave low-frequency
    /// mode immediately, rather than waiting for the next idle-clock tick.
    func recordUserInteraction() {
        evaluate()
    }

    private func observeWorkspaceLifecycle() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        addObserver(workspaceCenter, name: NSWorkspace.willSleepNotification) { [weak self] in
            self?.systemSleeping = true
            self?.evaluate()
        }
        addObserver(workspaceCenter, name: NSWorkspace.didWakeNotification) { [weak self] in
            self?.systemSleeping = false
            self?.displaySleeping = false
            self?.evaluate()
        }
        addObserver(workspaceCenter, name: NSWorkspace.screensDidSleepNotification) { [weak self] in
            self?.displaySleeping = true
            self?.evaluate()
        }
        addObserver(workspaceCenter, name: NSWorkspace.screensDidWakeNotification) { [weak self] in
            self?.displaySleeping = false
            self?.evaluate()
        }
    }

    private func observeScreenLockLifecycle() {
        let center = DistributedNotificationCenter.default()
        addObserver(center, name: Notification.Name("com.apple.screenIsLocked")) { [weak self] in
            self?.screenLocked = true
            self?.evaluate()
        }
        addObserver(center, name: Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in
            self?.screenLocked = false
            self?.evaluate()
        }
    }

    private func addObserver(
        _ center: NotificationCenter,
        name: Notification.Name,
        action: @escaping () -> Void
    ) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { _ in action() }
        observers.append((center, observer))
    }

    /// Re-evaluates policy without emitting work downstream unless it changed.
    /// Reconfiguring timers is reserved for lifecycle and setting changes; the
    /// repeating idle timer must not recreate itself every minute.
    private func evaluate(reconfigureTimers: Bool = false) {
        let newMode = resolvedMode(at: Date())
        let changed = newMode != mode
        mode = newMode
        if changed || reconfigureTimers {
            installBoundaryTimer()
            installIdleTimerIfNeeded()
        }
        if changed {
            onSamplingModeChanged?(newMode)
        }
    }

    private func resolvedMode(at date: Date) -> MonitoringSamplingMode {
        if settings.manualMonitoringPaused { return .paused(.manual) }
        if systemSleeping { return .paused(.systemSleep) }
        if displaySleeping { return .paused(.displaySleep) }
        if screenLocked { return .paused(.screenLocked) }
        if Self.nightScheduleIsActive(
            at: date,
            isEnabled: settings.nightMonitoringPauseEnabled,
            startSeconds: settings.nightMonitoringPauseStartSeconds,
            endSeconds: settings.nightMonitoringPauseEndSeconds
        ) {
            return .paused(.nightSchedule)
        }
        if !settings.backgroundMonitoringEnabled, !dashboardVisible {
            return .paused(.dashboardClosed)
        }
        guard settings.adaptiveSamplingEnabled, !dashboardVisible else { return .realtime }
        let idle = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: unsafeBitCast(UInt32.max, to: CGEventType.self)
        )
        return idle >= Self.idleThreshold ? .lowFrequency : .realtime
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

    private func installIdleTimerIfNeeded() {
        idleTimer?.cancel()
        idleTimer = nil
        guard settings.adaptiveSamplingEnabled, !mode.isPaused, !dashboardVisible else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 60, repeating: 60, leeway: .seconds(5))
        timer.setEventHandler { [weak self] in self?.evaluate() }
        timer.resume()
        idleTimer = timer
    }

    private static func nightScheduleIsActive(
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
