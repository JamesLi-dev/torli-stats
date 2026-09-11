import Combine
import Foundation
import CryptoKit

/// Reads only token-count events; no conversation text is retained or published.
final class CodexTokenActivityService: ObservableObject {
    @Published private(set) var records: [ActivityDay] = []
    @Published private(set) var isLoading = false
    @Published private(set) var status: String?
    private let homePaths: () -> [String]
    private let queue = DispatchQueue(label: "local.torli.stats.tokens", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var enabled = false
    private var paused = false
    private let cacheDirectory: URL
    private var loadedScope: String?
    private var displayedScope: String?
    private var refreshPending = false
    // Accessed only on the serial reader queue. Unchanged files are never reparsed.
    private var cache: [String: ScopedFile] = [:]

    struct ScopedFile: Codable {
        let homeScope: String
        let file: CachedFile
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    struct CachedFile: Codable {
        let modified: Date
        let size: Int
        let created: Date
        let offset: UInt64
        let previous: Double
        let events: [TokenEvent]
    }

    struct TokenEvent: Codable {
        let key: String
        let dateID: String
        let tokens: Double
    }

    init(homePaths: @escaping () -> [String], cacheDirectory: URL? = nil) {
        self.homePaths = homePaths
        self.cacheDirectory = cacheDirectory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("local.torli.stats/token-activity-v1", isDirectory: true)
        restoreSummary(scope: Self.scope(for: resolvedPaths()))
    }

    private func resolvedPaths() -> Set<URL> {
        Set(homePaths().map { path in
            let raw = path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? (ProcessInfo.processInfo.environment["CODEX_HOME"] ?? "~/.codex") : path
            return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath).standardizedFileURL
        })
    }

    private static func scope(for paths: Set<URL>) -> String {
        let identity = paths.map(\.path).sorted().joined(separator: "\n") + "|" + TimeZone.autoupdatingCurrent.identifier
        return "v2-" + digest(identity)
    }

    private func cacheURL(_ scope: String, _ kind: String) -> URL {
        cacheDirectory.appendingPathComponent("\(scope)-\(kind).json")
    }

    private func restoreSummary(scope: String) {
        guard displayedScope != scope else { return }
        displayedScope = scope
        records = (try? Data(contentsOf: cacheURL(scope, "summary")))
            .flatMap { try? JSONDecoder().decode([ActivityDay].self, from: $0) } ?? []
        status = nil
    }
    deinit { timer?.cancel() }

    func setEnabled(_ value: Bool) {
        enabled = value
        synchronize()
    }

    func setMonitoringPaused(_ value: Bool) {
        paused = value
        synchronize()
    }

    private func synchronize() {
        timer?.cancel()
        timer = nil
        guard enabled, !paused else { return }
        refresh()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 300, repeating: 300, leeway: .seconds(30))
        timer.setEventHandler { [weak self] in self?.refresh() }
        timer.resume()
        self.timer = timer
    }

    func refresh() {
        guard enabled else { return }
        guard !isLoading else { refreshPending = true; return }
        let paths = resolvedPaths()
        let scope = Self.scope(for: paths)
        restoreSummary(scope: scope)
        isLoading = true
        queue.async { [weak self] in
            guard let self else { return }
            if self.loadedScope != scope {
                self.cache = (try? Data(contentsOf: self.cacheURL(scope, "index")))
                    .flatMap { try? JSONDecoder().decode([String: ScopedFile].self, from: $0) } ?? [:]
                self.loadedScope = scope
            }
            var seen = Set<String>()
            var events: [String: TokenEvent] = [:]
            var failed = false
            var foundDirectory = false
            var cacheChanged = false
            for home in paths {
                let homeScope = Self.digest(home.path)
                for directory in ["sessions", "archived_sessions"] {
                    let root = home.appendingPathComponent(directory)
                    guard FileManager.default.fileExists(atPath: root.path) else { continue }
                    foundDirectory = true
                    guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey], options: [.skipsHiddenFiles], errorHandler: { _, _ in failed = true; return true }) else {
                        failed = true
                        continue
                    }
                    for case let file as URL in files where file.pathExtension == "jsonl" {
                        let fileKey = Self.digest(file.path)
                        seen.insert(fileKey)
                        do {
                            let attributes = try file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .creationDateKey])
                            let modified = attributes.contentModificationDate ?? .distantPast
                            let size = attributes.fileSize ?? 0
                            let created = attributes.creationDate ?? .distantPast
                            let cached = self.cache[fileKey]?.file
                            if cached?.modified != modified || cached?.size != size || cached?.created != created {
                                self.cache[fileKey] = ScopedFile(homeScope: homeScope, file: try Self.readIncrement(file, cached: cached))
                                cacheChanged = true
                            }
                            for event in self.cache[fileKey]?.file.events ?? [] { events[homeScope + "|" + event.key] = event }
                        } catch { failed = true }
                    }
                }
            }
            // An inaccessible directory must not erase already collected history.
            if !foundDirectory && !self.cache.isEmpty { failed = true }
            if !failed {
                let previousCount = self.cache.count
                self.cache = self.cache.filter { seen.contains($0.key) }
                cacheChanged = cacheChanged || self.cache.count != previousCount
            }
            if failed {
                for file in self.cache.values {
                    for event in file.file.events { events[file.homeScope + "|" + event.key] = event }
                }
            }
            var totals: [String: Double] = [:]
            for event in events.values { totals[event.dateID, default: 0] += event.tokens }
            let records = totals.sorted { $0.key < $1.key }.map { ActivityDay(dateID: $0.key, value: $0.value) }
            let message = failed ? "activity.read_failed" : (!foundDirectory || records.isEmpty ? "activity.tokens_empty" : nil)
            do {
                try FileManager.default.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
                if cacheChanged {
                    try JSONEncoder().encode(self.cache).write(to: self.cacheURL(scope, "index"), options: .atomic)
                }
                if !failed {
                    try JSONEncoder().encode(records).write(to: self.cacheURL(scope, "summary"), options: .atomic)
                }
                try Self.pruneCache(at: self.cacheDirectory, currentScope: scope)
            } catch {
                // Keep displaying data if disk caching is temporarily unavailable.
            }
            DispatchQueue.main.async {
                self.isLoading = false
                if Self.scope(for: self.resolvedPaths()) == scope {
                    if !failed || !records.isEmpty { self.records = records }
                    self.status = message.map { StatsL10n.text($0) }
                } else {
                    self.refreshPending = true
                }
                if self.refreshPending {
                    self.refreshPending = false
                    self.refresh()
                }
            }
        }
    }

    /// Keep the active scope and at most two recent scopes, for no more than 30 days.
    /// Unversioned v1 caches are discarded because their paths and totals are obsolete.
    static func pruneCache(at directory: URL, currentScope: String, now: Date = Date()) throws {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
        var scopes: [String: [(URL, Date)]] = [:]
        for file in files {
            let name = file.lastPathComponent
            guard let suffix = ["-index.json", "-summary.json"].first(where: { name.hasSuffix($0) }) else { continue }
            let scope = String(name.dropLast(suffix.count))
            let hash = scope.hasPrefix("v2-") ? String(scope.dropFirst(3)) : scope
            guard hash.count == 64, hash.allSatisfy({ "0123456789abcdef".contains($0) }) else { continue }
            let modified = try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            scopes[scope, default: []].append((file, modified))
        }
        let recent = scopes.keys.filter { scope in
            scope != currentScope && scope.hasPrefix("v2-") &&
                (scopes[scope]!.map(\.1).max() ?? .distantPast) >= now.addingTimeInterval(-30 * 86400)
        }.sorted { (scopes[$0]!.map(\.1).max() ?? .distantPast) > (scopes[$1]!.map(\.1).max() ?? .distantPast) }
        let retained = Set([currentScope] + Array(recent.prefix(2)))
        for (scope, entries) in scopes where !retained.contains(scope) {
            for (file, _) in entries { try FileManager.default.removeItem(at: file) }
        }
    }

    static func read(_ url: URL) throws -> [TokenEvent] {
        try readIncrement(url, cached: nil).events
    }

    static func readIncrement(_ url: URL, cached: CachedFile?) throws -> CachedFile {
        let attributes = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .creationDateKey])
        let size = attributes.fileSize ?? 0
        let created = attributes.creationDate ?? .distantPast
        // Truncation, replacement and same-size edits require rebuilding this file only.
        let resume = cached.flatMap { $0.created == created && size > $0.size ? $0 : nil }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var offset = resume?.offset ?? 0
        try handle.seek(toOffset: offset)
        var buffer = Data()
        var events: [TokenEvent] = resume?.events ?? []
        var previous = resume?.previous ?? 0
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()
        func consume(_ line: Data) {
            // Avoid decoding large message bodies and tool outputs.
            guard line.range(of: Data("\"token_count\"".utf8)) != nil,
                  let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  object["type"] as? String == "event_msg",
                  let payload = object["payload"] as? [String: Any], payload["type"] as? String == "token_count",
                  let info = payload["info"] as? [String: Any],
                  let usage = info["total_token_usage"] as? [String: Any],
                  let total = usage["total_tokens"] as? Double,
                  total.isFinite, total >= 0,
                  let timestamp = object["timestamp"] as? String,
                  let date = fractional.date(from: timestamp) ?? standard.date(from: timestamp) else { return }
            // Cumulative snapshots are often repeated alongside rate-limit events.
            let delta = total >= previous ? total - previous : total
            previous = total
            guard delta > 0 else { return }
            // Forks and archive copies can carry identical historical events.
            let key = "\(timestamp)|\(total)|\(delta)"
            events.append(TokenEvent(key: key, dateID: ActivityHeatmap.dateID(date), tokens: delta))
        }
        while let chunk = try handle.read(upToCount: 256 * 1024), !chunk.isEmpty {
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 10) {
                offset += UInt64(buffer.distance(from: buffer.startIndex, to: newline) + 1)
                consume(Data(buffer[..<newline]))
                buffer.removeSubrange(...newline)
            }
        }
        // An unterminated last line may still be in the middle of a write.
        return CachedFile(modified: attributes.contentModificationDate ?? .distantPast, size: size,
                          created: created, offset: offset, previous: previous, events: events)
    }
}
