import Foundation

struct CodexAccountConfiguration: Codable, Identifiable, Equatable {
    static let defaultAccountID = UUID(uuidString: "D8C4A85A-6264-4C66-A384-57246B328E8F")!

    let id: UUID
    var displayName: String
    var homePath: String
    var isDashboardVisible: Bool
    var isStatusBarIncluded: Bool

    var resolvedDisplayName: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? StatsL10n.text("codex.account") : trimmed
    }

    static func defaultAccount(
        homePath: String,
        displayName: String,
        isDashboardVisible: Bool,
        isStatusBarIncluded: Bool
    ) -> Self {
        Self(
            id: defaultAccountID,
            displayName: displayName,
            homePath: homePath,
            isDashboardVisible: isDashboardVisible,
            isStatusBarIncluded: isStatusBarIncluded
        )
    }
}

struct CodexRefreshSettings: Equatable {
    let isEnabled: Bool
    let intervalMinutes: Int
}

struct CodexHomeValidation {
    let resolvedPath: String
    let directoryExists: Bool
    let authFileExists: Bool
    let executablePath: String?

    var isReady: Bool {
        directoryExists && authFileExists && executablePath != nil
    }

    var summary: String {
        if !directoryExists { return StatsL10n.text("codex.home_missing") }
        if !authFileExists { return StatsL10n.text("codex.auth_missing") }
        if executablePath == nil { return StatsL10n.text("codex.executable_missing") }
        return StatsL10n.text("codex.home_ready")
    }
}

enum CodexUsageError: Error, LocalizedError {
    case codexHomeNotFound
    case authFileNotFound
    case executableNotFound
    case processLaunchFailed
    case initializeFailed
    case unauthorized
    case protocolError
    case invalidResponse
    case timeout
    case networkUnavailable
    case unsupportedAuthMode
    case processExited

    var isRetryable: Bool {
        switch self {
        case .timeout, .networkUnavailable, .processLaunchFailed, .initializeFailed, .protocolError, .invalidResponse, .processExited:
            return true
        case .codexHomeNotFound, .authFileNotFound, .executableNotFound, .unauthorized, .unsupportedAuthMode:
            return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .codexHomeNotFound: return StatsL10n.text("codex.home_not_found")
        case .authFileNotFound: return StatsL10n.text("codex.not_logged_in")
        case .executableNotFound: return StatsL10n.text("codex.cli_not_found")
        case .processLaunchFailed: return StatsL10n.text("codex.cli_launch_failed")
        case .initializeFailed: return StatsL10n.text("codex.initialization_failed")
        case .unauthorized: return StatsL10n.text("codex.login_expired")
        case .protocolError: return StatsL10n.text("codex.protocol_error")
        case .invalidResponse: return StatsL10n.text("codex.invalid_response")
        case .timeout: return StatsL10n.text("codex.refresh_timed_out")
        case .networkUnavailable: return StatsL10n.text("codex.network_unavailable")
        case .unsupportedAuthMode: return StatsL10n.text("codex.unsupported_auth")
        case .processExited: return StatsL10n.text("codex.process_exited")
        }
    }
}

struct CodexAccountIdentity {
    let email: String?
    let displayPrefix: String
    let planType: String?
}

struct CodexUsageWindow {
    let usedPercent: Double
    let windowDurationMinutes: Int?
    let resetsAt: Date?
}

struct CodexCredits {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: String?
}

struct CodexUsageSnapshot {
    let account: CodexAccountIdentity
    let primary: CodexUsageWindow?
    let secondary: CodexUsageWindow?
    let credits: CodexCredits?
    let rateLimitReachedType: String?
    let fetchedAt: Date

    func isStale(referenceDate: Date = Date(), maximumAge: TimeInterval = 15 * 60) -> Bool {
        referenceDate.timeIntervalSince(fetchedAt) > maximumAge
    }
}

enum CodexUsageState {
    case idle
    case loading(CodexUsageSnapshot?)
    case retrying(CodexUsageError, CodexUsageSnapshot?, attempt: Int, retryAt: Date)
    case available(CodexUsageSnapshot)
    case unavailable(CodexUsageError, CodexUsageSnapshot?)

    var snapshot: CodexUsageSnapshot? {
        switch self {
        case .idle: return nil
        case let .loading(snapshot): return snapshot
        case let .retrying(_, snapshot, _, _): return snapshot
        case let .available(snapshot): return snapshot
        case let .unavailable(_, snapshot): return snapshot
        }
    }
}
