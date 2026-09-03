import Combine
import Foundation
import Security

enum WakaTimeRange: String, CaseIterable, Identifiable {
    case last7Days = "last_7_days"
    case last30Days = "last_30_days"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .last7Days: return "近 7 天"
        case .last30Days: return "近 30 天"
        }
    }
}

struct WakaTimeBreakdown: Decodable, Identifiable, Equatable {
    let name: String
    let totalSeconds: Double
    let percent: Double
    let text: String

    var id: String { name }

    private enum CodingKeys: String, CodingKey {
        case name
        case totalSeconds = "total_seconds"
        case percent
        case text
    }
}

struct WakaTimeAIModel: Decodable, Identifiable, Equatable {
    let name: String
    let lines: Int
    let cost: Double

    var id: String { name }
}

struct WakaTimePeriod: Equatable {
    let totalSeconds: Double
    let activeDayCount: Int

    var averageActiveDaySeconds: Double {
        guard activeDayCount > 0 else { return 0 }
        return totalSeconds / Double(activeDayCount)
    }
}

struct WakaTimeSnapshot: Decodable, Equatable {
    let totalSeconds: Double
    let humanReadableTotal: String
    let languages: [WakaTimeBreakdown]
    let editors: [WakaTimeBreakdown]
    let categories: [WakaTimeBreakdown]
    let operatingSystems: [WakaTimeBreakdown]
    let aiInputTokens: Double
    let aiCachedInputTokens: Double
    let aiOutputTokens: Double
    let aiModelTotalCost: Double
    let aiModelBreakdown: [WakaTimeAIModel]

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

    init(from decoder: Decoder) throws {
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

enum WakaTimeUsageState: Equatable {
    case notConfigured
    case loading(WakaTimeSnapshot?)
    case available(WakaTimeSnapshot, refreshedAt: Date)
    case unavailable(String, WakaTimeSnapshot?)

    var snapshot: WakaTimeSnapshot? {
        switch self {
        case .available(let snapshot, _): return snapshot
        case .loading(let snapshot), .unavailable(_, let snapshot): return snapshot
        case .notConfigured: return nil
        }
    }

    var statusText: String {
        switch self {
        case .notConfigured: return "未配置 WakaTime API Key"
        case .loading: return "正在同步 WakaTime"
        case .available(_, let date): return "更新于 \(date.formatted(date: .omitted, time: .shortened))"
        case .unavailable(let message, _): return message
        }
    }
}

final class WakaTimeUsageStore: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    private(set) var state: WakaTimeUsageState = .notConfigured
    private(set) var snapshots: [WakaTimeRange: WakaTimeSnapshot] = [:]
    private(set) var todayPeriod: WakaTimePeriod?
    private(set) var lastSevenDaysPeriod: WakaTimePeriod?
    private(set) var lastThirtyDaysPeriod: WakaTimePeriod?

    private let apiKeyProvider: () -> String?
    private let rangeProvider: () -> WakaTimeRange
    private var refreshTimer: DispatchSourceTimer?
    private var refreshInFlight = false

    init(apiKeyProvider: @escaping () -> String?, rangeProvider: @escaping () -> WakaTimeRange) {
        self.apiKeyProvider = apiKeyProvider
        self.rangeProvider = rangeProvider
    }

    deinit {
        refreshTimer?.cancel()
    }

    func synchronize(isEnabled: Bool) {
        refreshTimer?.cancel()
        refreshTimer = nil

        guard isEnabled, apiKeyProvider() != nil else {
            update(.notConfigured)
            return
        }

        refresh()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .seconds(1_800), repeating: .seconds(1_800), leeway: .seconds(120))
        timer.setEventHandler { [weak self] in self?.refresh() }
        timer.resume()
        refreshTimer = timer
    }

    func refresh() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !refreshInFlight else { return }
        guard let apiKey = apiKeyProvider(), !apiKey.isEmpty else {
            update(.notConfigured)
            return
        }

        refreshInFlight = true
        update(.loading(snapshots[.last30Days]))

        let group = DispatchGroup()
        let lock = NSLock()
        var fetchedSnapshots: [WakaTimeRange: WakaTimeSnapshot] = [:]
        var fetchedTodayPeriod: WakaTimePeriod?
        var fetchedLastSevenDaysPeriod: WakaTimePeriod?
        var fetchedLastThirtyDaysPeriod: WakaTimePeriod?
        var fetchError: Error?

        for range in WakaTimeRange.allCases {
            group.enter()
            WakaTimeUsageClient.fetch(apiKey: apiKey, range: range) { result in
                lock.lock()
                switch result {
                case .success(let snapshot):
                    fetchedSnapshots[range] = snapshot
                case .failure(let error):
                    fetchError = fetchError ?? error
                }
                lock.unlock()
                group.leave()
            }
        }

        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: today)!
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: today)!

        group.enter()
        WakaTimeUsageClient.fetchPeriod(apiKey: apiKey, start: today, end: today) { result in
            lock.lock()
            switch result {
            case .success(let period): fetchedTodayPeriod = period
            case .failure(let error): fetchError = fetchError ?? error
            }
            lock.unlock()
            group.leave()
        }

        group.enter()
        WakaTimeUsageClient.fetchPeriod(apiKey: apiKey, start: sevenDaysAgo, end: yesterday) { result in
            lock.lock()
            switch result {
            case .success(let period): fetchedLastSevenDaysPeriod = period
            case .failure(let error): fetchError = fetchError ?? error
            }
            lock.unlock()
            group.leave()
        }

        group.enter()
        WakaTimeUsageClient.fetchPeriod(apiKey: apiKey, start: thirtyDaysAgo, end: yesterday) { result in
            lock.lock()
            switch result {
            case .success(let period): fetchedLastThirtyDaysPeriod = period
            case .failure(let error): fetchError = fetchError ?? error
            }
            lock.unlock()
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.refreshInFlight = false
            self.snapshots.merge(fetchedSnapshots) { _, new in new }
            self.todayPeriod = fetchedTodayPeriod ?? self.todayPeriod
            self.lastSevenDaysPeriod = fetchedLastSevenDaysPeriod ?? self.lastSevenDaysPeriod
            self.lastThirtyDaysPeriod = fetchedLastThirtyDaysPeriod ?? self.lastThirtyDaysPeriod
            if let snapshot = self.snapshots[.last30Days] {
                self.update(.available(snapshot, refreshedAt: Date()))
            } else if let fetchError {
                self.update(.unavailable(fetchError.localizedDescription, self.state.snapshot))
            } else {
                self.update(.unavailable("WakaTime 未返回统计数据", self.state.snapshot))
            }
        }
    }

    private func update(_ state: WakaTimeUsageState) {
        self.state = state
        objectWillChange.send()
    }
}

private enum WakaTimeUsageClient {
    private struct Response: Decodable {
        let data: WakaTimeSnapshot
    }

    private struct PeriodResponse: Decodable {
        let data: [DailySummary]
    }

    private struct DailySummary: Decodable {
        let grandTotal: DailyGrandTotal

        private enum CodingKeys: String, CodingKey {
            case grandTotal = "grand_total"
        }
    }

    private struct DailyGrandTotal: Decodable {
        let totalSeconds: Double

        private enum CodingKeys: String, CodingKey {
            case totalSeconds = "total_seconds"
        }
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

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Basic \("\(apiKey):".data(using: .utf8)!.base64EncodedString())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode), let data else {
                completion(.failure(URLError(.badServerResponse)))
                return
            }
            do {
                let days = try JSONDecoder().decode(PeriodResponse.self, from: data).data
                let totalSeconds = days.reduce(0) { $0 + $1.grandTotal.totalSeconds }
                completion(.success(WakaTimePeriod(
                    totalSeconds: totalSeconds,
                    activeDayCount: days.filter { $0.grandTotal.totalSeconds > 0 }.count
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

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Basic \("\(apiKey):".data(using: .utf8)!.base64EncodedString())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(URLError(.badServerResponse)))
                return
            }
            guard (200...299).contains(httpResponse.statusCode), let data else {
                let message: String
                switch httpResponse.statusCode {
                case 401: message = "API Key 无效或已失效"
                case 429: message = "WakaTime 请求过于频繁，请稍后重试"
                default: message = "WakaTime 请求失败（HTTP \(httpResponse.statusCode)）"
                }
                completion(.failure(WakaTimeClientError(message: message)))
                return
            }
            do {
                completion(.success(try JSONDecoder().decode(Response.self, from: data).data))
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
    private static let account = "api-key"

    static func readAPIKey() -> String? {
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
    static func saveAPIKey(_ value: String) -> Bool {
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
            return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    static func deleteAPIKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
