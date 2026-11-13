import Foundation

enum CodexLocalUsageReader {
    /// Only use recent records written after this home's current login. Never mix homes.
    static func snapshot(home: URL, now: Date = Date()) -> CodexUsageSnapshot? {
        let auth = home.appendingPathComponent("auth.json")
        guard let changed = try? auth.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
              let data = try? Data(contentsOf: auth),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = object["tokens"] as? [String: Any],
              let accountID = tokens["account_id"] as? String, !accountID.isEmpty else { return nil }
        var identity: [String: Any] = [:]
        if let token = tokens["id_token"] as? String, let email = claims(token)?["email"] as? String {
            identity["email"] = email
        }
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        let cutoff = max(changed, now.addingTimeInterval(-300))
        var files: [(URL, Date)] = []
        // A long-running session can live in an old date directory. Inspect metadata
        // throughout both trees, but read only bounded tails of recent candidates.
        for directory in ["sessions", "archived_sessions"] {
            guard let entries = FileManager.default.enumerator(at: home.appendingPathComponent(directory),
                includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in entries where url.pathExtension == "jsonl" {
                guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true,
                      let date = values.contentModificationDate, date >= cutoff else { continue }
                files.append((url, date))
                files.sort { $0.1 > $1.1 }
                if files.count > 24 { files.removeLast() }
            }
        }
        var latest: CodexUsageSnapshot?
        for (url, _) in files.prefix(24) {
            guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? handle.close() }
            guard let size = try? handle.seekToEnd() else { continue }
            let offset = size > 262144 ? size - 262144 : 0
            guard (try? handle.seek(toOffset: offset)) != nil,
                  let tail = try? handle.read(upToCount: 262144) else { continue }
            var lines = tail.split(separator: 10, omittingEmptySubsequences: false)
            if offset > 0, !lines.isEmpty { lines.removeFirst() }
            if tail.last != 10, !lines.isEmpty { lines.removeLast() }
            for line in lines.reversed() {
                guard line.range(of: Data("\"rate_limits\"".utf8)) != nil,
                      let event = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                      let snapshot = CodexUsageParser.sessionSnapshot(event, identity: identity, now: now, notBefore: changed) else { continue }
                if latest == nil || snapshot.fetchedAt > latest!.fetchedAt { latest = snapshot }
                break
            }
        }
        guard (try? auth.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) == changed else { return nil }
        return latest
    }

    private static func claims(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
