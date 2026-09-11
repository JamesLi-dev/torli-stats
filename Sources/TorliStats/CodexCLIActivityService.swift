import Combine
import Foundation

struct CodexCLIActivityDailyRecord: Codable, Identifiable, Equatable {
    let dateID: String
    var activeSeconds: TimeInterval

    var id: String { dateID }
}

/// Tracks only whether a process named `codex` exists. It never reads process
/// arguments, terminal output, project paths, or input. The persisted data is
/// limited to daily active duration and the most recent observation time.
final class CodexCLIActivityService: ObservableObject {
    private static let recordsKey = "codexCLIActivityDailyRecords"
    private static let lastActiveAtKey = "codexCLIActivityLastActiveAt"
    private static let retentionDays = 365
    private static let pollInterval: TimeInterval = 15
    private static let maximumCountedInterval: TimeInterval = pollInterval * 2

    @Published private(set) var isEnabled = false
    @Published private(set) var isMonitoringPaused = false
    @Published private(set) var isCodexRunning = false
    @Published private(set) var todayActiveSeconds: TimeInterval = 0
    @Published private(set) var dailyRecords: [CodexCLIActivityDailyRecord] = []
    @Published private(set) var lastActiveAt: Date?

    private let defaults: UserDefaults
    private var timer: DispatchSourceTimer?
    private var lastObservationAt: Date?
    private var wasRunning = false
    private var processCheckInFlight = false
    private var persistWorkItem: DispatchWorkItem?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadRecords()
        refreshPublishedValues()
    }

    deinit {
        timer?.cancel()
        persistWorkItem?.cancel()
        persistRecords()
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        if !enabled {
            closeCurrentObservation(at: Date())
        }
        isEnabled = enabled
        guard enabled, !isMonitoringPaused else {
            stopPolling()
            isCodexRunning = false
            return
        }
        installTimer()
    }

    func setMonitoringPaused(_ paused: Bool) {
        guard isMonitoringPaused != paused else { return }
        if paused {
            closeCurrentObservation(at: Date())
        }
        isMonitoringPaused = paused
        guard isEnabled else { return }
        if paused {
            stopPolling()
            isCodexRunning = false
        } else {
            installTimer()
        }
    }

    func clearHistory() {
        dailyRecords = []
        lastActiveAt = nil
        defaults.removeObject(forKey: Self.recordsKey)
        defaults.removeObject(forKey: Self.lastActiveAtKey)
        refreshPublishedValues()
    }

    /// Returns one aggregate record per calendar day, including zero-activity
    /// days so the seven-day trend remains chronological.
    func records(forLastDays dayCount: Int, endingAt date: Date = Date()) -> [CodexCLIActivityDailyRecord] {
        guard dayCount > 0 else { return [] }
        let calendar = Calendar.current
        let recordsByDay = dailyRecords.reduce(into: [String: CodexCLIActivityDailyRecord]()) { result, record in
            result[record.dateID] = record
        }

        return (0..<dayCount).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset - dayCount + 1, to: date) else { return nil }
            let id = Self.dayID(for: day)
            return recordsByDay[id] ?? CodexCLIActivityDailyRecord(dateID: id, activeSeconds: 0)
        }
    }

    private func installTimer() {
        guard timer == nil else { return }
        let newTimer = DispatchSource.makeTimerSource(queue: .main)
        newTimer.schedule(deadline: .now(), repeating: .seconds(Int(Self.pollInterval)), leeway: .seconds(3))
        newTimer.setEventHandler { [weak self] in
            self?.pollCodexProcess()
        }
        newTimer.resume()
        timer = newTimer
    }

    private func stopPolling() {
        timer?.cancel()
        timer = nil
        lastObservationAt = nil
        wasRunning = false
        processCheckInFlight = false
    }

    private func pollCodexProcess() {
        guard isEnabled, !isMonitoringPaused, !processCheckInFlight else { return }
        processCheckInFlight = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let isRunning = Self.isCodexProcessRunning()
            DispatchQueue.main.async {
                guard let self else { return }
                self.processCheckInFlight = false
                guard self.isEnabled, !self.isMonitoringPaused else { return }
                self.recordObservation(isRunning: isRunning, at: Date())
            }
        }
    }

    private func recordObservation(isRunning: Bool, at date: Date) {
        if let lastObservationAt, wasRunning {
            let elapsed = min(
                Self.maximumCountedInterval,
                max(0, date.timeIntervalSince(lastObservationAt))
            )
            if elapsed > 0 {
                addActivity(from: lastObservationAt, to: lastObservationAt.addingTimeInterval(elapsed))
            }
        }

        wasRunning = isRunning
        lastObservationAt = date
        isCodexRunning = isRunning
        if isRunning {
            lastActiveAt = date
            defaults.set(date, forKey: Self.lastActiveAtKey)
        }
    }

    private func closeCurrentObservation(at date: Date) {
        guard let observationStart = lastObservationAt, wasRunning else {
            lastObservationAt = nil
            wasRunning = false
            return
        }
        let elapsed = min(
            Self.maximumCountedInterval,
            max(0, date.timeIntervalSince(observationStart))
        )
        if elapsed > 0 {
            addActivity(from: observationStart, to: observationStart.addingTimeInterval(elapsed))
        }
        lastObservationAt = nil
        wasRunning = false
    }

    private func addActivity(from start: Date, to end: Date) {
        guard end > start else { return }
        let calendar = Calendar.current
        var cursor = start
        while cursor < end {
            let dayStart = calendar.startOfDay(for: cursor)
            let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? end
            let segmentEnd = min(end, nextDay)
            let seconds = segmentEnd.timeIntervalSince(cursor)
            if seconds > 0 {
                let dayID = Self.dayID(for: cursor)
                var record = dailyRecords.first(where: { $0.dateID == dayID })
                    ?? CodexCLIActivityDailyRecord(dateID: dayID, activeSeconds: 0)
                record.activeSeconds += seconds
                replace(record)
            }
            cursor = segmentEnd
        }
        refreshPublishedValues()
        schedulePersistence()
    }

    private func replace(_ record: CodexCLIActivityDailyRecord) {
        if let index = dailyRecords.firstIndex(where: { $0.dateID == record.dateID }) {
            dailyRecords[index] = record
        } else {
            dailyRecords.append(record)
        }
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.retentionDays, to: Date()) ?? .distantPast
        let cutoffID = Self.dayID(for: cutoff)
        dailyRecords = dailyRecords
            .filter { $0.dateID >= cutoffID }
            .sorted { $0.dateID < $1.dateID }
    }

    private func refreshPublishedValues() {
        let todayID = Self.dayID(for: Date())
        todayActiveSeconds = dailyRecords.first(where: { $0.dateID == todayID })?.activeSeconds ?? 0
    }

    private func loadRecords() {
        if let data = defaults.data(forKey: Self.recordsKey),
           let records = try? JSONDecoder().decode([CodexCLIActivityDailyRecord].self, from: data) {
            let cutoff = Calendar.current.date(byAdding: .day, value: -Self.retentionDays, to: Date()) ?? .distantPast
            let cutoffID = Self.dayID(for: cutoff)
            dailyRecords = records
                .filter { $0.dateID >= cutoffID }
                .sorted { $0.dateID < $1.dateID }
        }
        lastActiveAt = defaults.object(forKey: Self.lastActiveAtKey) as? Date
    }

    private func schedulePersistence() {
        persistWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.persistRecords() }
        persistWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: workItem)
    }

    private func persistRecords() {
        guard let data = try? JSONEncoder().encode(dailyRecords) else { return }
        defaults.set(data, forKey: Self.recordsKey)
        if let lastActiveAt {
            defaults.set(lastActiveAt, forKey: Self.lastActiveAtKey)
        }
    }

    private static func isCodexProcessRunning() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", "codex"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func dayID(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04lld-%02lld-%02lld", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
