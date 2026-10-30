import Combine
import Foundation
import Security
import CryptoKit

public enum WakaTimeRange: String, CaseIterable, Identifiable {
    case last7Days = "last_7_days"
    case last30Days = "last_30_days"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .last7Days: return StatsL10n.text("wakatime.last_7_days")
        case .last30Days: return StatsL10n.text("wakatime.last_30_days")
        }
    }
}

public struct WakaTimeBreakdown: Codable, Identifiable, Equatable {
    public let name: String
    public let totalSeconds: Double
    public let percent: Double
    public let text: String

    public var id: String { name }

    private enum CodingKeys: String, CodingKey {
        case name
        case totalSeconds = "total_seconds"
        case percent
        case text
    }

    init(name: String, totalSeconds: Double, percent: Double, text: String) {
        self.name = name
        self.totalSeconds = totalSeconds
        self.percent = percent
        self.text = text
    }
}

public struct WakaTimeAIModel: Codable, Identifiable, Equatable {
    public let name: String
    public let lines: Int
    public let cost: Double

    public var id: String { name }

    init(name: String, lines: Int, cost: Double) {
        self.name = name
        self.lines = lines
        self.cost = cost
    }
}

public struct WakaTimeDailyRecord: Codable, Identifiable, Equatable {
    public let dateID: String
    public let totalSeconds: Double
    public var aiTokens: Double? = nil

    public var id: String { dateID }
}

public struct WakaTimePeriod: Codable, Equatable {
    public let totalSeconds: Double
    public let activeDayCount: Int
    public let dailyRecords: [WakaTimeDailyRecord]

    public var averageActiveDaySeconds: Double {
        guard activeDayCount > 0 else { return 0 }
        return totalSeconds / Double(activeDayCount)
    }
}

public struct WakaTimeSnapshot: Codable, Equatable {
    public let totalSeconds: Double
    public let humanReadableTotal: String
    public let languages: [WakaTimeBreakdown]
    public let editors: [WakaTimeBreakdown]
    public let categories: [WakaTimeBreakdown]
    public let operatingSystems: [WakaTimeBreakdown]
    public let aiInputTokens: Double
    public let aiCachedInputTokens: Double
    public let aiOutputTokens: Double
    public let aiModelTotalCost: Double
    public let aiModelBreakdown: [WakaTimeAIModel]

    private enum CodingKeys: String, CodingKey {
        case totalSeconds = "total_seconds"
        case humanReadableTotal = "human_readable_total"
        case languages
        case editors
        case categories
        case operatingSystems = "operating_systems"
        case aiInputTokens = "ai_input_tokens"
        case aiCachedInputTokens = "ai_cached_input_tokens"
        case aiOutputTokens = "ai_output_tokens"
        case aiModelTotalCost = "ai_model_total_cost"
        case aiModelBreakdown = "ai_model_breakdown"
    }

    init(
        totalSeconds: Double,
        humanReadableTotal: String,
        languages: [WakaTimeBreakdown],
        editors: [WakaTimeBreakdown],
        categories: [WakaTimeBreakdown],
        operatingSystems: [WakaTimeBreakdown],
        aiInputTokens: Double,
        aiCachedInputTokens: Double,
        aiOutputTokens: Double,
        aiModelTotalCost: Double,
        aiModelBreakdown: [WakaTimeAIModel]
    ) {
        self.totalSeconds = totalSeconds
        self.humanReadableTotal = humanReadableTotal
        self.languages = languages
        self.editors = editors
        self.categories = categories
        self.operatingSystems = operatingSystems
        self.aiInputTokens = aiInputTokens
        self.aiCachedInputTokens = aiCachedInputTokens
        self.aiOutputTokens = aiOutputTokens
        self.aiModelTotalCost = aiModelTotalCost
        self.aiModelBreakdown = aiModelBreakdown
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalSeconds = try container.decode(Double.self, forKey: .totalSeconds)
        humanReadableTotal = try container.decode(String.self, forKey: .humanReadableTotal)
        languages = try container.decode([WakaTimeBreakdown].self, forKey: .languages)
        editors = try container.decode([WakaTimeBreakdown].self, forKey: .editors)
        categories = try container.decode([WakaTimeBreakdown].self, forKey: .categories)
        operatingSystems = try container.decode([WakaTimeBreakdown].self, forKey: .operatingSystems)
        aiInputTokens = try container.decodeIfPresent(Double.self, forKey: .aiInputTokens) ?? 0
        aiCachedInputTokens = try container.decodeIfPresent(Double.self, forKey: .aiCachedInputTokens) ?? 0
        aiOutputTokens = try container.decodeIfPresent(Double.self, forKey: .aiOutputTokens) ?? 0
        aiModelTotalCost = try container.decodeIfPresent(Double.self, forKey: .aiModelTotalCost) ?? 0
        aiModelBreakdown = try container.decodeIfPresent([WakaTimeAIModel].self, forKey: .aiModelBreakdown) ?? []
    }
}

private struct WakaTimeCachePayload: Codable {
    let version: Int
    let savedAt: Date
    let dateID: String
    let snapshots: [String: WakaTimeSnapshot]
    let todayPeriod: WakaTimePeriod?
    let lastSevenDaysPeriod: WakaTimePeriod?
    let lastThirtyDaysPeriod: WakaTimePeriod?
    let activityPeriod: WakaTimePeriod?
    let activityRefreshedAt: Date?
    let activityFullRefreshedAt: Date?
    let todaySnapshot: WakaTimeSnapshot?
}

public enum WakaTimeUsageState: Equatable {
    case notConfigured
    case loading(WakaTimeSnapshot?)
    case available(WakaTimeSnapshot, refreshedAt: Date)
    case unavailable(String, WakaTimeSnapshot?)

    public var snapshot: WakaTimeSnapshot? {
        switch self {
        case .available(let snapshot, _): return snapshot
        case .loading(let snapshot), .unavailable(_, let snapshot): return snapshot
        case .notConfigured: return nil
        }
    }

    public var statusText: String {
        switch self {
        case .notConfigured: return StatsL10n.text("wakatime.status.not_configured")
        case .loading: return StatsL10n.text("wakatime.status.syncing")
        case .available(_, let date): return StatsL10n.format("wakatime.status.updated_at", date.formatted(date: .omitted, time: .shortened))
        case .unavailable(let message, _): return message
        }
    }
}

public final class WakaTimeUsageStore: ObservableObject {
    public let objectWillChange = ObservableObjectPublisher()
    public private(set) var state: WakaTimeUsageState = .notConfigured
    public private(set) var snapshots: [WakaTimeRange: WakaTimeSnapshot] = [:]
    public private(set) var todayPeriod: WakaTimePeriod?
    public private(set) var lastSevenDaysPeriod: WakaTimePeriod?
    public private(set) var lastThirtyDaysPeriod: WakaTimePeriod?
    public private(set) var activityPeriod: WakaTimePeriod?
    public private(set) var activityLoading = false
    public private(set) var activityError: String?
    private var activityRefreshedAt: Date?
    private var activityFullRefreshedAt: Date?
    private var activityIdentity: String?
    private let cacheDirectory: URL
    private var cacheIdentity: String?
    private var cacheDateID: String?
    private var cacheSavedAt: Date?
    private var pendingActivityRefresh = false
    public private(set) var todaySnapshot: WakaTimeSnapshot?

    var dailyRecords: [WakaTimeDailyRecord] {
        switch rangeProvider() {
        case .last7Days: return lastSevenDaysPeriod?.dailyRecords ?? []
        case .last30Days: return lastThirtyDaysPeriod?.dailyRecords ?? []
        }
    }

    struct Requests {
        var snapshot: (String, WakaTimeRange, @escaping (Result<WakaTimeSnapshot, Error>) -> Void) -> Void = WakaTimeUsageClient.fetch
        var today: (String, Date, @escaping (Result<WakaTimeUsageClient.DailyData, Error>) -> Void) -> Void = WakaTimeUsageClient.fetchCurrentDay
        var period: (String, Date, Date, @escaping (Result<WakaTimePeriod, Error>) -> Void) -> Void = WakaTimeUsageClient.fetchPeriod
    }
    private let historyEnabled: Bool
    private let requests: Requests

    private let apiKeyProvider: () -> String?
    private let rangeProvider: () -> WakaTimeRange
    private var refreshTimer: DispatchSourceTimer?
    private var refreshInFlight = false
    private var requestGeneration = UUID()
    private var requestIdentity: String?
    private var pendingSnapshotRange: WakaTimeRange?
    private var isEnabled = false
    private var automaticRefreshPaused = false

    init(apiKeyProvider: @escaping () -> String?, rangeProvider: @escaping () -> WakaTimeRange, cacheDirectory: URL? = nil, requests: Requests = Requests(), historyEnabled: Bool = false) {
        self.historyEnabled = historyEnabled
        self.requests = requests
        self.apiKeyProvider = apiKeyProvider
        self.rangeProvider = rangeProvider
        self.cacheDirectory = cacheDirectory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("local.torli.stats/wakatime-v1", isDirectory: true)
        restoreCacheIfAvailable()
    }

    deinit {
        refreshTimer?.cancel()
    }

    func synchronize(isEnabled: Bool) {
        let requestedIdentity = apiKeyProvider()
        if requestIdentity != requestedIdentity || self.isEnabled != isEnabled {
            requestGeneration = UUID()
            requestIdentity = requestedIdentity
            refreshInFlight = false
            activityLoading = false
            pendingSnapshotRange = nil
            pendingActivityRefresh = false
        }
        self.isEnabled = isEnabled
        guard let apiKey = apiKeyProvider(), !apiKey.isEmpty else {
            clearCachedData()
            update(.notConfigured)
            refreshTimer?.cancel()
            refreshTimer = nil
            return
        }
        let identity = Self.cacheIdentity(for: apiKey)
        if cacheIdentity != identity {
            clearCachedData()
            cacheIdentity = identity
            restoreCacheIfAvailable()
        }
        if !isEnabled || activityIdentity != apiKeyProvider() {
            activityPeriod = nil
            activityRefreshedAt = nil
            activityFullRefreshedAt = nil
            activityError = nil
            activityIdentity = apiKeyProvider()
            objectWillChange.send()
        }
        refreshTimer?.cancel()
        refreshTimer = nil

        guard isEnabled else {
            update(.notConfigured)
            return
        }
        guard !automaticRefreshPaused else { return }

        refreshAutomatically()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .seconds(1_800), repeating: .seconds(1_800), leeway: .seconds(120))
        timer.setEventHandler { [weak self] in self?.refreshAutomatically() }
        timer.resume()
        refreshTimer = timer
    }

    func setAutomaticRefreshPaused(_ paused: Bool) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard automaticRefreshPaused != paused else { return }
        automaticRefreshPaused = paused
        if paused {
            refreshTimer?.cancel()
            refreshTimer = nil
        } else {
            synchronize(isEnabled: isEnabled)
        }
    }

    public func period(for range: WakaTimeRange) -> WakaTimePeriod? {
        switch range {
        case .last7Days: return lastSevenDaysPeriod
        case .last30Days: return lastThirtyDaysPeriod
        }
    }

    /// Fetch a year only when the development statistics view needs it.
    public func loadActivity(force: Bool = false) {
        guard historyEnabled else { return }
        guard isEnabled, !activityLoading, let apiKey = apiKeyProvider(), !apiKey.isEmpty else { return }
        if activityIdentity != apiKey {
            activityPeriod = nil
            activityRefreshedAt = nil
            activityFullRefreshedAt = nil
            activityIdentity = apiKey
        }
        if !force, activityPeriod != nil, !activityCalibrationDue {
            refreshCurrentDay()
            return
        }
        if refreshInFlight {
            pendingActivityRefresh = force
            return
        }
        if !force, let refreshed = activityRefreshedAt, Date().timeIntervalSince(refreshed) < 1_800 { return }
        activityLoading = true
        let generation = requestGeneration
        activityError = nil
        objectWillChange.send()
        let today = Date()
        let fullHistory = force || activityPeriod == nil || activityFullRefreshedAt.map { today.timeIntervalSince($0) >= 7 * 86400 } != false
        let start = Calendar.current.date(byAdding: .day, value: fullHistory ? -364 : -2, to: today)!
        requests.period(apiKey, start, today) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.acceptsResponse(apiKey: apiKey, generation: generation) else { return }
                self.activityLoading = false
                guard self.isEnabled, self.apiKeyProvider() == apiKey else {
                    self.objectWillChange.send()
                    return
                }
                switch result {
                case .success(let period):
                    self.activityPeriod = fullHistory ? period : Self.mergingRecentHistory(self.activityPeriod, recent: period, start: start, end: today)
                    self.activityRefreshedAt = Date()
                    if fullHistory { self.activityFullRefreshedAt = Date() }
                    self.persistCache()
                case .failure:
                    self.activityError = StatsL10n.text("activity.wakatime_history_error")
                }
                self.objectWillChange.send()
            }
        }
    }

    /// User-initiated refreshes fetch the selected range and historical periods.
    /// Automatic refreshes use `refreshCurrentDay()` once this cache is warm.
    public func refresh() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard historyEnabled else { refreshCurrentDay(force: true); return }
        guard isEnabled else { return }
        guard !refreshInFlight else {
            // A range change while the regular refresh is running should still
            // populate the requested breakdown once that work finishes.
            pendingSnapshotRange = rangeProvider()
            return
        }
        guard let apiKey = apiKeyProvider(), !apiKey.isEmpty else {
            update(.notConfigured)
            return
        }

        refreshInFlight = true
        let generation = requestGeneration
        update(.loading(snapshots[.last30Days]))

        let group = DispatchGroup()
        let lock = NSLock()
        var fetchedSnapshots: [WakaTimeRange: WakaTimeSnapshot] = [:]
        var fetchedTodayData: WakaTimeUsageClient.DailyData?
        var fetchedLastThirtyDaysPeriod: WakaTimePeriod?
        var fetchError: Error?

        // The Dashboard only displays the selected breakdown. Fetching both
        // 7- and 30-day breakdowns every cycle doubled that request for no
        // visible benefit; the other range is loaded when its detail view opens.
        let selectedRange = rangeProvider()
        group.enter()
        requests.snapshot(apiKey, selectedRange) { result in
            lock.lock()
            switch result {
            case .success(let snapshot):
                fetchedSnapshots[selectedRange] = snapshot
            case .failure(let error):
                fetchError = fetchError ?? error
            }
            lock.unlock()
            group.leave()
        }

        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: today)!

        group.enter()
        requests.today(apiKey, today) { result in
            lock.lock()
            switch result {
            case .success(let data): fetchedTodayData = data
            case .failure(let error): fetchError = fetchError ?? error
            }
            lock.unlock()
            group.leave()
        }

        group.enter()
        requests.period(apiKey, thirtyDaysAgo, yesterday) { result in
            lock.lock()
            switch result {
            case .success(let period): fetchedLastThirtyDaysPeriod = period
            case .failure(let error): fetchError = fetchError ?? error
            }
            lock.unlock()
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self, self.acceptsResponse(apiKey: apiKey, generation: generation) else { return }
            self.refreshInFlight = false
            self.snapshots.merge(fetchedSnapshots) { _, new in new }
            self.todayPeriod = fetchedTodayData?.period ?? self.todayPeriod
            self.todaySnapshot = fetchedTodayData?.snapshot ?? self.todaySnapshot
            self.lastThirtyDaysPeriod = fetchedLastThirtyDaysPeriod ?? self.lastThirtyDaysPeriod
            self.lastSevenDaysPeriod = fetchedLastThirtyDaysPeriod.map {
                Self.trailingPeriod($0, days: 7, endingAt: today)
            } ?? self.lastSevenDaysPeriod
            let fullRefreshCompleted = fetchedSnapshots[self.rangeProvider()] != nil
                && fetchedTodayData != nil
                && fetchedLastThirtyDaysPeriod != nil
            if fullRefreshCompleted {
                self.cacheDateID = Self.dateID(for: today)
            }
            self.persistCache()
            if let snapshot = self.snapshots[self.rangeProvider()] {
                self.update(.available(snapshot, refreshedAt: Date()))
            } else if let fetchError {
                self.update(.unavailable(fetchError.localizedDescription, self.state.snapshot))
            } else {
                self.update(.unavailable(StatsL10n.text("wakatime.error.no_data"), self.state.snapshot))
            }
            self.drainPendingRequests()
        }
    }

    /// Loads a breakdown on demand for the detailed-statistics range picker.
    /// Daily periods are already derived from the regular refresh and do not
    /// require another request here.
    public func loadSnapshotIfNeeded(for range: WakaTimeRange) {
        guard historyEnabled else { return }
        dispatchPrecondition(condition: .onQueue(.main))
        guard isEnabled, snapshots[range] == nil,
              let apiKey = apiKeyProvider(), !apiKey.isEmpty else { return }
        guard !refreshInFlight else {
            pendingSnapshotRange = range
            return
        }
        refreshInFlight = true
        let generation = requestGeneration
        requests.snapshot(apiKey, range) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.acceptsResponse(apiKey: apiKey, generation: generation) else { return }
                self.refreshInFlight = false
                switch result {
                case let .success(snapshot):
                    self.snapshots[range] = snapshot
                    self.persistCache()
                    if let current = self.snapshots[self.rangeProvider()] {
                        self.update(.available(current, refreshedAt: Date()))
                    }
                case let .failure(error):
                    self.update(.unavailable(error.localizedDescription, self.state.snapshot))
                }
                self.drainPendingRequests()
            }
        }
    }

    private func acceptsResponse(apiKey: String, generation: UUID) -> Bool {
        isEnabled && apiKeyProvider() == apiKey && requestGeneration == generation
    }

    private func drainPendingRequests() {
        guard isEnabled, !refreshInFlight else { return }
        if let range = pendingSnapshotRange {
            pendingSnapshotRange = nil
            loadSnapshotIfNeeded(for: range)
            if refreshInFlight { return }
        }
        if pendingActivityRefresh || (activityPeriod != nil && activityCalibrationDue) {
            let force = pendingActivityRefresh
            pendingActivityRefresh = false
            loadActivity(force: force)
        }
    }

    private var activityCalibrationDue: Bool {
        guard let refreshed = activityRefreshedAt, let full = activityFullRefreshedAt else { return true }
        return !Calendar.autoupdatingCurrent.isDateInToday(refreshed) || Date().timeIntervalSince(full) >= 7 * 86400
    }

    static func mergingRecentHistory(_ base: WakaTimePeriod?, recent: WakaTimePeriod, start: Date, end: Date) -> WakaTimePeriod {
        let startID = dateID(for: start)
        let endID = dateID(for: end)
        let firstID = dateID(for: Calendar.autoupdatingCurrent.date(byAdding: .day, value: -364, to: end)!)
        var records = Dictionary((base?.dailyRecords ?? []).filter { $0.dateID < startID && $0.dateID >= firstID }.map { ($0.dateID, $0) }, uniquingKeysWith: { _, new in new })
        for record in recent.dailyRecords where record.dateID >= startID && record.dateID <= endID {
            records[record.dateID] = record
        }
        let days = records.values.sorted { $0.dateID < $1.dateID }
        return WakaTimePeriod(totalSeconds: days.reduce(0) { $0 + $1.totalSeconds }, activeDayCount: days.filter { $0.totalSeconds > 0 }.count, dailyRecords: days)
    }

    private func refreshAutomatically() {
        guard !automaticRefreshPaused else { return }
        if hasCachedData, todaySnapshot != nil, todayPeriod != nil, cacheDateID == Self.dateID(for: Date()) {
            refreshCurrentDay()
        } else {
            refresh()
        }
    }

    private var hasCachedData: Bool {
        !snapshots.isEmpty || todayPeriod != nil || lastThirtyDaysPeriod != nil || activityPeriod != nil
    }

    private func refreshCurrentDay(force: Bool = false) {
        guard isEnabled, (force || !automaticRefreshPaused), !refreshInFlight,
              let apiKey = apiKeyProvider(), !apiKey.isEmpty else { return }
        refreshInFlight = true
        let generation = requestGeneration
        update(.loading(historyEnabled ? snapshots[rangeProvider()] : todaySnapshot))
        let today = Calendar.autoupdatingCurrent.startOfDay(for: Date())
        let todayID = Self.dateID(for: today)
        requests.today(apiKey, today) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.acceptsResponse(apiKey: apiKey, generation: generation) else { return }
                self.refreshInFlight = false
                switch result {
                case .success(let data):
                    self.todayPeriod = data.period
                    // The existing 7/30-day cards intentionally exclude today;
                    // their cached historical ranges remain valid until the next
                    // full refresh rolls the window forward.
                    self.activityPeriod = Self.replaceToday(in: self.activityPeriod, with: data.period, days: 365, endingAt: today)

                    if let previous = self.todaySnapshot {
                        self.snapshots = self.snapshots.mapValues { Self.replacingToday(in: $0, previous: previous, current: data.snapshot) }
                    }
                    self.todaySnapshot = data.snapshot
                    self.cacheDateID = todayID
                    self.persistCache()
                    if let snapshot = self.historyEnabled ? self.snapshots[self.rangeProvider()] : self.todaySnapshot {
                        self.update(.available(snapshot, refreshedAt: Date()))
                    }
                case .failure(let error):
                    if let snapshot = self.snapshots[self.rangeProvider()] {
                        self.update(.unavailable(error.localizedDescription, snapshot))
                    } else {
                        self.update(.unavailable(error.localizedDescription, self.state.snapshot))
                    }
                }
                self.drainPendingRequests()
            }
        }
    }

    private static func trailingPeriod(
        _ period: WakaTimePeriod,
        days: Int,
        endingAt date: Date
    ) -> WakaTimePeriod {
        let calendar = Calendar.autoupdatingCurrent
        let end = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: date)) ?? date
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: end) ?? end
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let startID = formatter.string(from: start)
        let endID = formatter.string(from: end)
        let records = period.dailyRecords.filter { $0.dateID >= startID && $0.dateID <= endID }
        return WakaTimePeriod(
            totalSeconds: records.reduce(0) { $0 + $1.totalSeconds },
            activeDayCount: records.filter { $0.totalSeconds > 0 }.count,
            dailyRecords: records
        )
    }

    private static func replaceToday(
        in base: WakaTimePeriod?,
        with today: WakaTimePeriod,
        days: Int,
        endingAt date: Date
    ) -> WakaTimePeriod? {
        guard let base else { return nil }
        let calendar = Calendar.autoupdatingCurrent
        let todayStart = calendar.startOfDay(for: date)
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: todayStart) ?? todayStart
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let startID = formatter.string(from: start)
        let todayID = formatter.string(from: todayStart)
        var records = Dictionary(base.dailyRecords.map { ($0.dateID, $0) }, uniquingKeysWith: { _, new in new })
        if let currentRecord = today.dailyRecords.first(where: { $0.dateID == todayID }) {
            records[todayID] = currentRecord
        } else {
            records[todayID] = WakaTimeDailyRecord(dateID: todayID, totalSeconds: 0, aiTokens: 0)
        }
        let filtered = records.values.filter { $0.dateID >= startID && $0.dateID <= todayID }.sorted { $0.dateID < $1.dateID }
        return WakaTimePeriod(
            totalSeconds: filtered.reduce(0) { $0 + $1.totalSeconds },
            activeDayCount: filtered.filter { $0.totalSeconds > 0 }.count,
            dailyRecords: filtered
        )
    }

    private static func replacingToday(
        in base: WakaTimeSnapshot,
        previous: WakaTimeSnapshot?,
        current: WakaTimeSnapshot
    ) -> WakaTimeSnapshot {
        guard let previous else { return base }
        let totalSeconds = max(0, base.totalSeconds - previous.totalSeconds + current.totalSeconds)
        return WakaTimeSnapshot(
            totalSeconds: totalSeconds,
            humanReadableTotal: formatDuration(totalSeconds),
            languages: mergeBreakdowns(base.languages, previous.languages, current.languages, total: totalSeconds),
            editors: mergeBreakdowns(base.editors, previous.editors, current.editors, total: totalSeconds),
            categories: mergeBreakdowns(base.categories, previous.categories, current.categories, total: totalSeconds),
            operatingSystems: mergeBreakdowns(base.operatingSystems, previous.operatingSystems, current.operatingSystems, total: totalSeconds),
            aiInputTokens: max(0, base.aiInputTokens - previous.aiInputTokens + current.aiInputTokens),
            aiCachedInputTokens: max(0, base.aiCachedInputTokens - previous.aiCachedInputTokens + current.aiCachedInputTokens),
            aiOutputTokens: max(0, base.aiOutputTokens - previous.aiOutputTokens + current.aiOutputTokens),
            aiModelTotalCost: max(0, base.aiModelTotalCost - previous.aiModelTotalCost + current.aiModelTotalCost),
            aiModelBreakdown: mergeModels(base.aiModelBreakdown, previous.aiModelBreakdown, current.aiModelBreakdown)
        )
    }

    private static func mergeBreakdowns(
        _ base: [WakaTimeBreakdown],
        _ previous: [WakaTimeBreakdown],
        _ current: [WakaTimeBreakdown],
        total: Double
    ) -> [WakaTimeBreakdown] {
        let names = Set(base.map(\.name)).union(previous.map(\.name)).union(current.map(\.name))
        return names.compactMap { name in
            let seconds = max(0,
                (base.first { $0.name == name }?.totalSeconds ?? 0)
                - (previous.first { $0.name == name }?.totalSeconds ?? 0)
                + (current.first { $0.name == name }?.totalSeconds ?? 0)
            )
            guard seconds > 0 else { return nil }
            return WakaTimeBreakdown(
                name: name,
                totalSeconds: seconds,
                percent: total > 0 ? seconds / total * 100 : 0,
                text: formatDuration(seconds)
            )
        }
        .sorted { $0.totalSeconds > $1.totalSeconds }
    }

    private static func mergeModels(
        _ base: [WakaTimeAIModel],
        _ previous: [WakaTimeAIModel],
        _ current: [WakaTimeAIModel]
    ) -> [WakaTimeAIModel] {
        let names = Set(base.map(\.name)).union(previous.map(\.name)).union(current.map(\.name))
        return names.compactMap { name in
            let lines = max(0,
                (base.first { $0.name == name }?.lines ?? 0)
                - (previous.first { $0.name == name }?.lines ?? 0)
                + (current.first { $0.name == name }?.lines ?? 0)
            )
            let cost = max(0,
                (base.first { $0.name == name }?.cost ?? 0)
                - (previous.first { $0.name == name }?.cost ?? 0)
                + (current.first { $0.name == name }?.cost ?? 0)
            )
            guard lines > 0 || cost > 0 else { return nil }
            return WakaTimeAIModel(name: name, lines: lines, cost: cost)
        }
        .sorted { $0.lines > $1.lines }
    }

    private static func formatDuration(_ seconds: Double) -> String {
        let minutes = max(0, Int(seconds / 60))
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    private static func dateID(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func cacheIdentity(for apiKey: String) -> String {
        let value = "\(apiKey)|\(TimeZone.autoupdatingCurrent.identifier)"
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func cacheURL(for identity: String) -> URL {
        cacheDirectory.appendingPathComponent("\(identity).json")
    }

    private func restoreCacheIfAvailable() {
        guard let apiKey = apiKeyProvider(), !apiKey.isEmpty else { return }
        let identity = Self.cacheIdentity(for: apiKey)
        guard let data = try? Data(contentsOf: cacheURL(for: identity)),
              let payload = try? JSONDecoder().decode(WakaTimeCachePayload.self, from: data),
              payload.version == 1 else { return }
        cacheIdentity = identity
        cacheDateID = payload.dateID
        cacheSavedAt = payload.savedAt
        snapshots = Dictionary(uniqueKeysWithValues: payload.snapshots.compactMap { key, value in
            guard let range = WakaTimeRange(rawValue: key) else { return nil }
            return (range, value)
        })
        todayPeriod = payload.dateID == Self.dateID(for: Date()) ? payload.todayPeriod : nil
        lastSevenDaysPeriod = payload.lastSevenDaysPeriod
        lastThirtyDaysPeriod = payload.lastThirtyDaysPeriod
        activityPeriod = payload.activityPeriod
        activityRefreshedAt = payload.activityRefreshedAt
        activityFullRefreshedAt = payload.activityFullRefreshedAt
        todaySnapshot = payload.dateID == Self.dateID(for: Date()) ? payload.todaySnapshot : nil
        activityIdentity = apiKey
        if let snapshot = historyEnabled ? snapshots[rangeProvider()] : todaySnapshot {
            state = .available(snapshot, refreshedAt: payload.savedAt)
        }
    }

    private func persistCache() {
        guard let apiKey = apiKeyProvider(), !apiKey.isEmpty else { return }
        let identity = Self.cacheIdentity(for: apiKey)
        let payload = WakaTimeCachePayload(
            version: 1,
            savedAt: Date(),
            dateID: cacheDateID ?? Self.dateID(for: Date()),
            snapshots: Dictionary(uniqueKeysWithValues: snapshots.map { ($0.key.rawValue, $0.value) }),
            todayPeriod: todayPeriod,
            lastSevenDaysPeriod: lastSevenDaysPeriod,
            lastThirtyDaysPeriod: lastThirtyDaysPeriod,
            activityPeriod: activityPeriod,
            activityRefreshedAt: activityRefreshedAt,
            activityFullRefreshedAt: activityFullRefreshedAt,
            todaySnapshot: todaySnapshot
        )
        do {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try JSONEncoder().encode(payload).write(to: cacheURL(for: identity), options: .atomic)
            cacheIdentity = identity
            cacheSavedAt = payload.savedAt
        } catch {
            // Cached UI data remains valid if the system cache is unavailable.
        }
    }

    private func clearCachedData() {
        snapshots = [:]
        todayPeriod = nil
        lastSevenDaysPeriod = nil
        lastThirtyDaysPeriod = nil
        activityPeriod = nil
        activityRefreshedAt = nil
        activityFullRefreshedAt = nil
        todaySnapshot = nil
        cacheDateID = nil
        cacheSavedAt = nil
        activityIdentity = nil
    }

    private func update(_ state: WakaTimeUsageState) {
        self.state = state
        objectWillChange.send()
    }
}

enum WakaTimeUsageClient {
    /// Keep credentials out of query strings and use the same auth for all endpoints.
    static func authenticatedRequest(url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    static func responseData(_ data: Data?, response: URLResponse?) throws -> Data {
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200...299).contains(response.statusCode) else {
            let message: String
            switch response.statusCode {
            case 401: message = StatsL10n.text("wakatime.error.invalid_token")
            case 403: message = StatsL10n.text("wakatime.error.forbidden")
            case 429: message = StatsL10n.text("wakatime.error.rate_limited")
            default: message = StatsL10n.format("wakatime.error.http", response.statusCode)
            }
            throw WakaTimeClientError(message: message)
        }
        guard let data else { throw URLError(.badServerResponse) }
        return data
    }

    struct DailyData {
        let period: WakaTimePeriod
        let snapshot: WakaTimeSnapshot
    }

    private struct Response: Decodable {
        let data: WakaTimeSnapshot
    }

    private struct PeriodResponse: Decodable {
        let data: [DailySummary]
    }

    private struct DailySummary: Decodable {
        let grandTotal: DailyGrandTotal
        let range: DailyRange?
        let languages: [WakaTimeBreakdown]
        let editors: [WakaTimeBreakdown]
        let categories: [WakaTimeBreakdown]
        let operatingSystems: [WakaTimeBreakdown]

        private enum CodingKeys: String, CodingKey {
            case grandTotal = "grand_total"
            case range
            case languages
            case editors
            case categories
            case operatingSystems = "operating_systems"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            grandTotal = try container.decode(DailyGrandTotal.self, forKey: .grandTotal)
            range = try container.decodeIfPresent(DailyRange.self, forKey: .range)
            languages = try container.decodeIfPresent([WakaTimeBreakdown].self, forKey: .languages) ?? []
            editors = try container.decodeIfPresent([WakaTimeBreakdown].self, forKey: .editors) ?? []
            categories = try container.decodeIfPresent([WakaTimeBreakdown].self, forKey: .categories) ?? []
            operatingSystems = try container.decodeIfPresent([WakaTimeBreakdown].self, forKey: .operatingSystems) ?? []
        }
    }

    private struct DailyRange: Decodable {
        let date: String?
    }

    private struct DailyGrandTotal: Decodable {
        let totalSeconds: Double
        let aiInputTokens: Double?
        let aiCachedInputTokens: Double?
        let aiOutputTokens: Double?
        let aiModelTotalCost: Double?
        let aiModelBreakdown: [WakaTimeAIModel]

        private enum CodingKeys: String, CodingKey {
            case totalSeconds = "total_seconds"
            case aiInputTokens = "ai_input_tokens"
            case aiOutputTokens = "ai_output_tokens"
            case aiCachedInputTokens = "ai_cached_input_tokens"
            case aiModelTotalCost = "ai_model_total_cost"
            case aiModelBreakdown = "ai_model_breakdown"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            totalSeconds = try container.decode(Double.self, forKey: .totalSeconds)
            aiInputTokens = try container.decodeIfPresent(Double.self, forKey: .aiInputTokens)
            aiCachedInputTokens = try container.decodeIfPresent(Double.self, forKey: .aiCachedInputTokens)
            aiOutputTokens = try container.decodeIfPresent(Double.self, forKey: .aiOutputTokens)
            aiModelTotalCost = try container.decodeIfPresent(Double.self, forKey: .aiModelTotalCost)
            aiModelBreakdown = try container.decodeIfPresent([WakaTimeAIModel].self, forKey: .aiModelBreakdown) ?? []
        }
    }

    static func fetchCurrentDay(
        apiKey: String,
        date: Date,
        completion: @escaping (Result<DailyData, Error>) -> Void
    ) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        let dateID = formatter.string(from: date)
        guard let url = URL(string: "https://api.wakatime.com/api/v1/users/current/summaries?start=\(dateID)&end=\(dateID)") else {
            completion(.failure(URLError(.badURL)))
            return
        }
        let request = authenticatedRequest(url: url, token: apiKey)
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error { completion(.failure(error)); return }
            let body: Data
            do { body = try responseData(data, response: response) }
            catch { completion(.failure(error)); return }
            do {
                let days = try JSONDecoder().decode(PeriodResponse.self, from: body).data
                guard let day = days.first else {
                    let empty = WakaTimeSnapshot(totalSeconds: 0, humanReadableTotal: "0 mins", languages: [], editors: [], categories: [], operatingSystems: [], aiInputTokens: 0, aiCachedInputTokens: 0, aiOutputTokens: 0, aiModelTotalCost: 0, aiModelBreakdown: [])
                    completion(.success(DailyData(period: WakaTimePeriod(totalSeconds: 0, activeDayCount: 0, dailyRecords: []), snapshot: empty)))
                    return
                }
                let total = day.grandTotal.totalSeconds
                let record = WakaTimeDailyRecord(
                    dateID: day.range?.date ?? dateID,
                    totalSeconds: total,
                    aiTokens: day.grandTotal.aiInputTokens.flatMap { input in day.grandTotal.aiOutputTokens.map { input + $0 } }
                )
                let snapshot = WakaTimeSnapshot(
                    totalSeconds: total,
                    humanReadableTotal: WakaTimeUsageClient.formatDuration(total),
                    languages: day.languages,
                    editors: day.editors,
                    categories: day.categories,
                    operatingSystems: day.operatingSystems,
                    aiInputTokens: day.grandTotal.aiInputTokens ?? 0,
                    aiCachedInputTokens: day.grandTotal.aiCachedInputTokens ?? 0,
                    aiOutputTokens: day.grandTotal.aiOutputTokens ?? 0,
                    aiModelTotalCost: day.grandTotal.aiModelTotalCost ?? 0,
                    aiModelBreakdown: day.grandTotal.aiModelBreakdown
                )
                completion(.success(DailyData(
                    period: WakaTimePeriod(totalSeconds: total, activeDayCount: total > 0 ? 1 : 0, dailyRecords: [record]),
                    snapshot: snapshot
                )))
            } catch { completion(.failure(error)) }
        }.resume()
    }

    private static func formatDuration(_ seconds: Double) -> String {
        let minutes = max(0, Int(seconds / 60))
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    static func fetchPeriod(
        apiKey: String,
        start: Date,
        end: Date,
        completion: @escaping (Result<WakaTimePeriod, Error>) -> Void
    ) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        let urlString = "https://api.wakatime.com/api/v1/users/current/summaries?start=\(formatter.string(from: start))&end=\(formatter.string(from: end))"
        guard let url = URL(string: urlString) else {
            completion(.failure(URLError(.badURL)))
            return
        }

        let request = authenticatedRequest(url: url, token: apiKey)
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            let body: Data
            do { body = try responseData(data, response: response) }
            catch { completion(.failure(error)); return }
            do {
                let days = try JSONDecoder().decode(PeriodResponse.self, from: body).data
                let totalSeconds = days.reduce(0) { $0 + $1.grandTotal.totalSeconds }
                let dailyRecords = days.compactMap { day -> WakaTimeDailyRecord? in
                    guard let dateID = day.range?.date, !dateID.isEmpty else { return nil }
                    let total = day.grandTotal
                    let tokens = total.aiInputTokens.flatMap { input in total.aiOutputTokens.map { input + $0 } }
                    return WakaTimeDailyRecord(dateID: dateID, totalSeconds: total.totalSeconds, aiTokens: tokens)
                }
                completion(.success(WakaTimePeriod(
                    totalSeconds: totalSeconds,
                    activeDayCount: days.filter { $0.grandTotal.totalSeconds > 0 }.count,
                    dailyRecords: dailyRecords.sorted { $0.dateID < $1.dateID }
                )))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    static func fetch(
        apiKey: String,
        range: WakaTimeRange,
        completion: @escaping (Result<WakaTimeSnapshot, Error>) -> Void
    ) {
        guard let url = URL(string: "https://api.wakatime.com/api/v1/users/current/stats/\(range.rawValue)") else {
            completion(.failure(URLError(.badURL)))
            return
        }

        let request = authenticatedRequest(url: url, token: apiKey)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            let body: Data
            do { body = try responseData(data, response: response) }
            catch { completion(.failure(error)); return }
            do {
                completion(.success(try JSONDecoder().decode(Response.self, from: body).data))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}

private struct WakaTimeClientError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum WakaTimeKeychain {
    private static let service = "local.torli.stats.wakatime"
    private static let account = "oauth-token"
    private static let legacyAccount = "api-key"

    static func readOAuthToken() -> String? { read(account: account) }
    /// Migration only needs to know that an old item exists, not read its secret.
    /// Never interrupt rendering Settings with a legacy-key authorization prompt.
    static var hasLegacyAPIKey: Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: legacyAccount,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    private static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else { return nil }
        return key
    }

    @discardableResult
    static func saveOAuthToken(_ value: String) -> Bool {
        guard !value.isEmpty, !value.contains(where: { $0.isWhitespace || $0.isNewline }) else { return false }
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { return false }
        } else if status != errSecSuccess { return false }
        // Remove the old credential only after the new one is safely stored.
        delete(account: legacyAccount)
        return true
    }

    static func deleteCredentials() {
        delete(account: account)
        delete(account: legacyAccount)
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
