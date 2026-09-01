import Combine
import Foundation

struct AppUpdateRelease: Equatable {
    let version: String
    let downloadURL: URL
    let publishedAt: Date?
}

enum AppUpdateCheckStatus: Equatable {
    case idle
    case checking
    case upToDate(Date)
    case available(AppUpdateRelease)
    case failed

    var description: String {
        switch self {
        case .idle: return "尚未检查更新"
        case .checking: return "正在检查更新…"
        case let .upToDate(date): return "已是最新版本（检查于 \(date.formatted(date: .abbreviated, time: .shortened))）"
        case let .available(release): return "发现新版本 \(release.version)"
        case .failed: return "暂时无法检查更新"
        }
    }
}

final class AppUpdateChecker: ObservableObject {
    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/JamesLi-dev/torli-stats/releases/latest")!
    private static let checkInterval: TimeInterval = 24 * 60 * 60
    private static let lastCheckKey = "appUpdateLastCheckDate"

    @Published private(set) var status: AppUpdateCheckStatus = .idle
    private let defaults: UserDefaults
    private var task: URLSessionDataTask?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func checkIfNeeded(isEnabled: Bool, completion: ((AppUpdateRelease?) -> Void)? = nil) {
        guard isEnabled else { return }
        let lastCheck = defaults.object(forKey: Self.lastCheckKey) as? Date
        guard lastCheck.map({ Date().timeIntervalSince($0) >= Self.checkInterval }) ?? true else { return }
        check(completion: completion)
    }

    func check(completion: ((AppUpdateRelease?) -> Void)? = nil) {
        guard task == nil else { return }
        status = .checking

        var request = URLRequest(url: Self.latestReleaseURL)
        request.timeoutInterval = 12
        request.setValue("TorliStats/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.task = nil
                self.defaults.set(Date(), forKey: Self.lastCheckKey)

                guard error == nil,
                      let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode),
                      let data,
                      let release = Self.parseRelease(data),
                      let remoteVersion = Version(release.version),
                      let installedVersion = Version(self.currentVersion) else {
                    self.status = .failed
                    completion?(nil)
                    return
                }

                if remoteVersion > installedVersion {
                    self.status = .available(release)
                    completion?(release)
                } else {
                    self.status = .upToDate(Date())
                    completion?(nil)
                }
            }
        }
        task?.resume()
    }

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    private static func parseRelease(_ data: Data) -> AppUpdateRelease? {
        struct GitHubRelease: Decodable {
            let tag_name: String
            let html_url: URL
            let published_at: Date?
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let release = try? decoder.decode(GitHubRelease.self, from: data) else { return nil }
        return AppUpdateRelease(
            version: release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV ")),
            downloadURL: release.html_url,
            publishedAt: release.published_at
        )
    }

    private struct Version: Comparable {
        let components: [Int]

        init?(_ rawValue: String) {
            let values = rawValue
                .trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                .split(separator: ".")
                .compactMap { Int($0) }
            guard !values.isEmpty else { return nil }
            components = values
        }

        static func < (lhs: Version, rhs: Version) -> Bool {
            let count = max(lhs.components.count, rhs.components.count)
            for index in 0..<count {
                let left = index < lhs.components.count ? lhs.components[index] : 0
                let right = index < rhs.components.count ? rhs.components[index] : 0
                if left != right { return left < right }
            }
            return false
        }
    }
}
