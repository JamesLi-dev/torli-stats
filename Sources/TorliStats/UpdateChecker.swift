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
        case .idle: return StatsL10n.text("update.idle")
        case .checking: return StatsL10n.text("update.checking")
        case let .upToDate(date): return StatsL10n.format("update.up_to_date", date.formatted(date: .abbreviated, time: .shortened))
        case let .available(release): return StatsL10n.format("update.available", release.version)
        case .failed: return StatsL10n.text("update.failed")
        }
    }
}

final class AppUpdateChecker: ObservableObject {
    // The GitHub REST API has a shared unauthenticated quota of 60 requests per
    // IP. The release page redirects to the latest tag without consuming that
    // API quota, so it remains reliable for users behind shared networks.
    private static let latestReleaseURL = URL(string: "https://github.com/JamesLi-dev/torli-stats/releases/latest")!
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
        request.httpMethod = "HEAD"
        request.setValue("TorliStats/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.task = nil

                guard error == nil,
                      let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode),
                      let release = Self.parseReleaseRedirect(response),
                      let remoteVersion = Version(release.version),
                      let installedVersion = Version(self.currentVersion) else {
                    self.status = .failed
                    completion?(nil)
                    return
                }

                self.defaults.set(Date(), forKey: Self.lastCheckKey)
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

    private static func parseReleaseRedirect(_ response: URLResponse?) -> AppUpdateRelease? {
        guard let url = response?.url else { return nil }
        let marker = "/releases/tag/"
        guard let range = url.path.range(of: marker) else { return nil }
        let tag = String(url.path[range.upperBound...])
        guard !tag.isEmpty else { return nil }
        return AppUpdateRelease(
            version: tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV ")),
            downloadURL: url,
            publishedAt: nil
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
