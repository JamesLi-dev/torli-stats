import Foundation

enum CodexUsageParser {
    static func isUnauthorized(_ error: [String: Any]) -> Bool {
        if let code = error["code"] as? NSNumber, [401, 403].contains(code.intValue) { return true }
        if let data = error["data"] as? [String: Any] {
            for key in ["status", "statusCode", "status_code", "httpStatus"] {
                if let value = number(data[key]), value == 401 || value == 403 { return true }
            }
            if isUnauthorized(data) { return true }
        }
        let message = (error["message"] as? String ?? "").lowercased()
        return ["unauthorized", "authentication required", "not authenticated", "not logged in",
                "token expired", "token has expired", "invalid access token", "please log in", "please sign in"]
            .contains { message.contains($0) }
    }

    static func sessionSnapshot(_ event: [String: Any], identity: [String: Any]?, now: Date,
                                notBefore: Date, maximumAge: TimeInterval = 300) -> CodexUsageSnapshot? {
        guard event["type"] as? String == "event_msg",
              let payload = event["payload"] as? [String: Any], payload["type"] as? String == "token_count",
              let limits = payload["rate_limits"] as? [String: Any],
              limits["limit_id"] == nil || limits["limit_id"] as? String == "codex",
              let timestamp = event["timestamp"] as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fractional = formatter.date(from: timestamp)
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = fractional ?? formatter.date(from: timestamp), date >= notBefore,
              date <= now, now.timeIntervalSince(date) <= maximumAge else { return nil }
        func window(_ raw: Any?) -> [String: Any]? {
            guard let raw = raw as? [String: Any] else { return nil }
            return ["usedPercent": raw["used_percent"] ?? NSNull(),
                    "windowDurationMins": raw["window_minutes"] ?? NSNull(),
                    "resetsAt": raw["resets_at"] ?? NSNull()]
        }
        var normalized: [String: Any] = ["primary": window(limits["primary"]) ?? [:]]
        normalized["secondary"] = window(limits["secondary"])
        normalized["planType"] = limits["plan_type"]
        normalized["rateLimitReachedType"] = limits["rate_limit_reached_type"]
        if let credits = limits["credits"] as? [String: Any] {
            normalized["credits"] = ["hasCredits": credits["has_credits"] ?? false,
                                     "unlimited": credits["unlimited"] ?? false,
                                     "balance": credits["balance"] ?? NSNull()]
        }
        guard let result = try? makeSnapshot(account: identity, rateLimits: normalized, fetchedAt: date),
              [result.primary, result.secondary].compactMap({ $0 }).allSatisfy({
                  $0.resetsAt.map { $0 > now } == true
              }) else { return nil }
        return result
    }
    static func makeSnapshot(account: [String: Any]?, rateLimits: [String: Any], fetchedAt: Date = Date()) throws -> CodexUsageSnapshot {
        let accountObject = account?["account"] as? [String: Any] ?? account ?? [:]
        let email = accountObject["email"] as? String
        let planType = (accountObject["planType"] as? String)
            ?? (rateLimits["rateLimits"] as? [String: Any])?["planType"] as? String
            ?? rateLimits["planType"] as? String
        let rateLimitsObject = rateLimits["rateLimits"] as? [String: Any] ?? rateLimits
        guard let primaryObject = rateLimitsObject["primary"] as? [String: Any] else {
            throw CodexUsageError.invalidResponse
        }
        guard let primary = parseWindow(primaryObject) else {
            throw CodexUsageError.invalidResponse
        }

        let secondary = (rateLimitsObject["secondary"] as? [String: Any]).flatMap(parseWindow)
        let credits = parseCredits(rateLimitsObject["credits"])
        let prefix = Self.displayPrefix(for: email)
        let identity = CodexAccountIdentity(email: email, displayPrefix: prefix, planType: planType)

        return CodexUsageSnapshot(
            account: identity,
            primary: primary,
            secondary: secondary,
            credits: credits,
            rateLimitReachedType: rateLimitsObject["rateLimitReachedType"] as? String,
            fetchedAt: fetchedAt
        )
    }

    static func parseWindow(_ object: [String: Any]) -> CodexUsageWindow? {
        guard let usedPercent = number(object["usedPercent"]), usedPercent.isFinite else { return nil }
        let duration = number(object["windowDurationMins"]).flatMap { $0.isFinite && $0 > 0 && $0 < Double(Int.max) ? Int($0) : nil }
        let resetsAt = number(object["resetsAt"]).flatMap { $0.isFinite && $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
        return CodexUsageWindow(
            usedPercent: min(100, max(0, usedPercent)),
            windowDurationMinutes: duration,
            resetsAt: resetsAt
        )
    }

    static func parseCredits(_ value: Any?) -> CodexCredits? {
        guard let object = value as? [String: Any] else { return nil }
        let hasCredits = object["hasCredits"] as? Bool ?? false
        let unlimited = object["unlimited"] as? Bool ?? false
        let balance: String?
        if let string = object["balance"] as? String {
            balance = string
        } else if let number = object["balance"] as? NSNumber {
            balance = number.stringValue
        } else {
            balance = nil
        }
        return CodexCredits(hasCredits: hasCredits, unlimited: unlimited, balance: balance)
    }

    static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    static func displayPrefix(for email: String?) -> String {
        guard let email,
              let localPart = email.split(separator: "@", maxSplits: 1).first,
              !localPart.isEmpty else {
            return "C"
        }
        let prefix = String(localPart.prefix(3)).uppercased()
        return prefix.isEmpty ? "C" : prefix
    }

    static func responseID(from value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

}
