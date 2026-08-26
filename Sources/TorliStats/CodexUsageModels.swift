import Foundation

struct CodexAccountConfiguration: Codable, Identifiable, Equatable {
    static let defaultAccountID = UUID(uuidString: "D8C4A85A-6264-4C66-A384-57246B328E8F")!

    let id: UUID
    var displayName: String
    var homePath: String
    var isDashboardVisible: Bool
    var isStatusBarIncluded: Bool

    static func defaultAccount(homePath: String, isDashboardVisible: Bool, isStatusBarIncluded: Bool) -> Self {
        Self(
            id: defaultAccountID,
            displayName: "默认账号",
            homePath: homePath,
            isDashboardVisible: isDashboardVisible,
            isStatusBarIncluded: isStatusBarIncluded
        )
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

    var errorDescription: String? {
        switch self {
        case .codexHomeNotFound: return "未找到 Codex Home"
        case .authFileNotFound: return "Codex 尚未登录"
        case .executableNotFound: return "未找到 Codex CLI"
        case .processLaunchFailed: return "无法启动 Codex CLI"
        case .initializeFailed: return "Codex 初始化失败"
        case .unauthorized: return "Codex 登录已失效"
        case .protocolError: return "Codex 协议错误"
        case .invalidResponse: return "Codex 返回数据无法识别"
        case .timeout: return "Codex 刷新超时"
        case .networkUnavailable: return "网络不可用"
        case .unsupportedAuthMode: return "当前 Codex 认证方式暂不支持"
        case .processExited: return "Codex CLI 意外退出"
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
}

enum CodexUsageState {
    case idle
    case loading(CodexUsageSnapshot?)
    case available(CodexUsageSnapshot)
    case unavailable(CodexUsageError, CodexUsageSnapshot?)

    var snapshot: CodexUsageSnapshot? {
        switch self {
        case .idle: return nil
        case let .loading(snapshot): return snapshot
        case let .available(snapshot): return snapshot
        case let .unavailable(_, snapshot): return snapshot
        }
    }
}
