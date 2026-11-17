import Combine
import Foundation

struct AppUpdateRelease: Equatable {
    let version: String
    let downloadURL: URL
    let publishedAt: Date?
}

enum AppUpdateCheckStatus: Equatable {
    case idle
    case unavailable
    case checking
    case upToDate(Date)
    case available(AppUpdateRelease)
    case failed

    var description: String {
        switch self {
        case .unavailable: return StatsL10n.text("update.unavailable")
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
    private let session: URLSession
    private var generation: UInt64 = 0
    private var task: URLSessionDataTask?
    private var completions: [(AppUpdateRelease?) -> Void] = []
    var installationController: UpdateInstallationController?
    var checkingController: UpdateCheckController?

    init(defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.session = session
        self.defaults = defaults
        if !checksAvailable { status = .unavailable }
    }

    func checkIfNeeded(isEnabled: Bool, completion: ((AppUpdateRelease?) -> Void)? = nil) {
        guard isEnabled, checksAvailable else { return }
        let lastCheck = defaults.object(forKey: Self.lastCheckKey) as? Date
        guard lastCheck.map({ Date().timeIntervalSince($0) >= Self.checkInterval }) ?? true else { return }
        check(completion: completion)
    }

    func check(completion: ((AppUpdateRelease?) -> Void)? = nil) {
        guard checksAvailable else {
            status = .unavailable
            completion?(nil)
            return
        }
        if let completion { completions.append(completion) }
        guard task == nil else { return }
        status = .checking
        generation &+= 1
        let requestGeneration = generation

        var request = URLRequest(url: Self.latestReleaseURL)
        request.timeoutInterval = 12
        request.httpMethod = "HEAD"
        request.setValue("TorliStats/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        task = session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self, self.generation == requestGeneration else { return }
                self.task = nil

                guard error == nil,
                      let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode),
                      let release = Self.parseReleaseRedirect(response),
                      let remoteVersion = Version(release.version),
                      let installedVersion = Version(self.currentVersion) else {
                    self.status = .failed
                    self.finishCheck(nil)
                    return
                }

                self.defaults.set(Date(), forKey: Self.lastCheckKey)
                if remoteVersion > installedVersion {
                    self.status = .available(release)
                    self.finishCheck(release)
                } else {
                    self.status = .upToDate(Date())
                    self.finishCheck(nil)
                }
            }
        }
        task?.resume()
    }

    func cancelCheck() {
        guard task != nil else { return }
        generation &+= 1
        task?.cancel()
        task = nil
        completions.removeAll()
        status = .idle
    }

    private func finishCheck(_ release: AppUpdateRelease?) {
        let callbacks = completions
        completions.removeAll()
        callbacks.forEach { $0(release) }
    }

    var checksAvailable: Bool {
        Bundle.main.object(forInfoDictionaryKey: "TorliUpdateChecksDisabled") as? Bool != true
    }

    var currentVersion: String {
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

// Release notes are untrusted text. The API URL is built only from a validated
// official release tag, and the response is bounded while it is received.
enum AppUpdateReleaseNotes {
    static let maximumResponseBytes = 512 * 1024
    private static let tagPattern = #"\A[vV]?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-((?:0|[1-9][0-9]*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*)(?:\.(?:0|[1-9][0-9]*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*))*))?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?\z"#

    static func requestURL(for release: AppUpdateRelease) -> URL? {
        guard let components = URLComponents(url: release.downloadURL, resolvingAgainstBaseURL: false),
              components.scheme == "https", components.host == "github.com",
              components.user == nil, components.password == nil, components.port == nil,
              components.query == nil, components.fragment == nil else { return nil }
        let prefix = "/JamesLi-dev/torli-stats/releases/tag/"
        guard components.path.hasPrefix(prefix) else { return nil }
        let tag = String(components.path.dropFirst(prefix.count))
        guard tag.range(of: tagPattern, options: .regularExpression) != nil else { return nil }
        let version = tag.first == "v" || tag.first == "V" ? String(tag.dropFirst()) : tag
        guard version == release.version else { return nil }
        var api = URLComponents()
        api.scheme = "https"
        api.host = "api.github.com"
        api.path = "/repos/JamesLi-dev/torli-stats/releases/tags/\(tag)"
        return api.url
    }

    static func parse(_ data: Data, expectedTag: String) -> String? {
        guard data.count <= maximumResponseBytes,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["tag_name"] as? String == expectedTag,
              let body = json["body"] else { return nil }
        if body is NSNull { return "" }
        return body as? String
    }

    static func load(release: AppUpdateRelease, completion: @escaping (String?) -> Void) {
        guard let url = requestURL(for: release) else {
            completion(nil)
            return
        }
        let delegate = ReleaseNotesRequest(url: url, tag: release.downloadURL.lastPathComponent, completion: completion)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("TorliStats", forHTTPHeaderField: "User-Agent")
        session.dataTask(with: request).resume()
    }
}

private final class ReleaseNotesRequest: NSObject, URLSessionDataDelegate {
    private let url: URL
    private let tag: String
    private let completion: (String?) -> Void
    private var data = Data()
    private var accepted = false

    init(url: URL, tag: String, completion: @escaping (String?) -> Void) {
        self.url = url
        self.tag = tag
        self.completion = completion
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        accepted = response.url == url && (response as? HTTPURLResponse)?.statusCode == 200 &&
            (response.expectedContentLength < 0 || response.expectedContentLength <= Int64(AppUpdateReleaseNotes.maximumResponseBytes))
        completionHandler(accepted ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        guard chunk.count <= AppUpdateReleaseNotes.maximumResponseBytes - data.count else {
            accepted = false
            dataTask.cancel()
            return
        }
        data.append(chunk)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let notes = error == nil && accepted ? AppUpdateReleaseNotes.parse(data, expectedTag: tag) : nil
        session.finishTasksAndInvalidate()
        DispatchQueue.main.async { self.completion(notes) }
    }
}
