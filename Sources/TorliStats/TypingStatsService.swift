import AppKit
import Combine
import CoreGraphics
import Foundation

struct TypingDailyRecord: Codable, Identifiable, Equatable {
    let dateID: String
    var keyCount: Int
    var activeSeconds: TimeInterval

    var id: String { dateID }
}

enum TypingStatsPermissionStatus: Equatable {
    case disabled
    case needsPermission
    case monitoring
    case unavailable

    var description: String {
        switch self {
        case .disabled: return "输入统计未启用"
        case .needsPermission: return "需要“输入监控”权限"
        case .monitoring: return "正在本机统计，不记录输入内容"
        case .unavailable: return "输入监控暂不可用"
        }
    }
}

final class TypingStatsService: ObservableObject {
    private static let recordsKey = "typingStatsDailyRecords"
    private static let retentionDays = 365
    private static let activeGap: TimeInterval = 30
    private static let speedWindow: TimeInterval = 60

    @Published private(set) var permissionStatus: TypingStatsPermissionStatus = .disabled
    @Published private(set) var todayKeyCount = 0
    @Published private(set) var totalKeyCount = 0
    @Published private(set) var activeSeconds: TimeInterval = 0
    @Published private(set) var keysPerMinute = 0
    @Published private(set) var dailyRecords: [TypingDailyRecord] = []

    private let defaults: UserDefaults
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var speedTimestamps: [Date] = []
    private var lastInputAt: Date?
    private var persistWorkItem: DispatchWorkItem?
    private var speedTimer: DispatchSourceTimer?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadRecords()
        refreshPublishedValues()
    }

    deinit {
        stopMonitoring()
        persistWorkItem?.cancel()
        persistRecords()
        speedTimer?.cancel()
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled else {
            stopMonitoring()
            permissionStatus = .disabled
            return
        }
        startMonitoringIfPermitted()
    }

    func requestPermissionAndStart() {
        guard CGPreflightListenEventAccess() || CGRequestListenEventAccess() else {
            permissionStatus = .needsPermission
            return
        }
        startMonitoringIfPermitted()
    }

    func openInputMonitoringSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else { return }
        NSWorkspace.shared.open(url)
    }

    func clearHistory() {
        dailyRecords = []
        lastInputAt = nil
        speedTimestamps = []
        defaults.removeObject(forKey: Self.recordsKey)
        refreshPublishedValues()
    }

    /// Returns one aggregate record per calendar day, including zero-input days,
    /// so charts remain chronological instead of visually skipping quiet days.
    func records(forLastDays dayCount: Int, endingAt date: Date = Date()) -> [TypingDailyRecord] {
        guard dayCount > 0 else { return [] }
        let calendar = Calendar.current
        let countsByDay = dailyRecords.reduce(into: [String: TypingDailyRecord]()) { result, record in
            result[record.dateID] = record
        }

        return (0..<dayCount).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset - dayCount + 1, to: date) else { return nil }
            let id = Self.dayID(for: day)
            return countsByDay[id] ?? TypingDailyRecord(dateID: id, keyCount: 0, activeSeconds: 0)
        }
    }

    private func startMonitoringIfPermitted() {
        guard CGPreflightListenEventAccess() else {
            permissionStatus = .needsPermission
            return
        }
        guard eventTap == nil else {
            permissionStatus = .monitoring
            return
        }

        let events = CGEventMask(1) << CGEventType.keyDown.rawValue
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: events,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<TypingStatsService>.fromOpaque(userInfo).takeUnretainedValue()
                service.handleEvent(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            permissionStatus = .unavailable
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        installSpeedTimer()
        permissionStatus = .monitoring
    }

    private func stopMonitoring() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        speedTimer?.cancel()
        speedTimer = nil
        speedTimestamps = []
        keysPerMinute = 0
    }

    private func handleEvent(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
        case .keyDown:
            guard isEligibleTextInput(event) else { return }
            recordInput(at: Date())
        default:
            break
        }
    }

    private func isEligibleTextInput(_ event: CGEvent) -> Bool {
        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl) { return false }

        // Modifier, navigation, function, and deletion keys do not represent
        // text entry. We intentionally retain space, return, option, and IME
        // candidate-confirmation keys so all input sources are counted alike.
        let excludedKeyCodes: Set<Int64> = [
            48, 51, 53, 55, 56, 57, 58, 59, 60, 61, 62, 63,
            64, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81,
            90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100,
            101, 103, 105, 106, 107, 109, 111, 113, 114,
            115, 116, 117, 118, 119, 120, 121, 122, 123, 124,
            125, 126
        ]
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        return !excludedKeyCodes.contains(keyCode)
    }

    private func recordInput(at date: Date) {
        let dayID = Self.dayID(for: date)
        var record = dailyRecords.first(where: { $0.dateID == dayID })
            ?? TypingDailyRecord(dateID: dayID, keyCount: 0, activeSeconds: 0)
        record.keyCount += 1
        if let lastInputAt {
            let gap = date.timeIntervalSince(lastInputAt)
            if gap > 0, gap <= Self.activeGap {
                record.activeSeconds += gap
            }
        }
        lastInputAt = date
        replace(record)

        speedTimestamps.append(date)
        updateSpeed(now: date)
        refreshPublishedValues()
        schedulePersistence()
    }

    private func updateSpeed(now: Date) {
        speedTimestamps.removeAll { now.timeIntervalSince($0) > Self.speedWindow }
        keysPerMinute = speedTimestamps.count
    }

    private func installSpeedTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            self?.updateSpeed(now: Date())
        }
        timer.resume()
        speedTimer = timer
    }

    private func replace(_ record: TypingDailyRecord) {
        if let index = dailyRecords.firstIndex(where: { $0.dateID == record.dateID }) {
            dailyRecords[index] = record
        } else {
            dailyRecords.append(record)
        }
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.retentionDays, to: Date()) ?? .distantPast
        let cutoffID = Self.dayID(for: cutoff)
        dailyRecords = dailyRecords.filter { $0.dateID >= cutoffID }.sorted { $0.dateID < $1.dateID }
    }

    private func refreshPublishedValues() {
        let today = dailyRecords.first(where: { $0.dateID == Self.dayID(for: Date()) })
        todayKeyCount = today?.keyCount ?? 0
        activeSeconds = today?.activeSeconds ?? 0
        totalKeyCount = dailyRecords.reduce(0) { $0 + $1.keyCount }
    }

    private func loadRecords() {
        guard let data = defaults.data(forKey: Self.recordsKey),
              let records = try? JSONDecoder().decode([TypingDailyRecord].self, from: data) else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.retentionDays, to: Date()) ?? .distantPast
        let cutoffID = Self.dayID(for: cutoff)
        dailyRecords = records
            .filter { $0.dateID >= cutoffID }
            .sorted { $0.dateID < $1.dateID }
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
    }

    private static func dayID(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
