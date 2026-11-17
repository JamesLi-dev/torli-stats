import AppKit
import CryptoKit
import Darwin
import Foundation

// The release checksum and archive are served by the same publisher. This detects
// corruption, not an attacker who can replace both assets; ad-hoc signatures
// likewise establish bundle integrity, not the publisher's identity.
private enum UpdateFailure: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case let .message(text) = self { return text }
        return nil
    }
}

private var updateUsesChinese: Bool {
    (Bundle.main.preferredLocalizations.first ?? Locale.preferredLanguages.first ?? "").lowercased().hasPrefix("zh")
}

private func updateText(_ english: String, _ chinese: String) -> String {
    updateUsesChinese ? chinese : english
}

private func updateError(_ message: String) -> Error {
    guard updateUsesChinese else { return UpdateFailure.message(message) }
    let chinese: String
    switch message {
    case "The selected release is not newer than the installed app.": chinese = "所选版本不比当前安装版本新。"
    case "The release does not have a trusted GitHub semantic-version tag.": chinese = "发行版本不是来自指定 GitHub 仓库的有效版本标签。"
    case "This is not a valid Community app; Pro and unrecognized bundles cannot be replaced.": chinese = "这不是有效的社区版应用；不能替换 Pro 或无法识别的应用。"
    case "Only the installed Community app at /Applications/TorliStats.app can be updated. Development, temporary, renamed and symlinked copies must be updated manually.": chinese = "只能更新安装在 /Applications/TorliStats.app 的社区版。开发、临时、改名或符号链接副本请手动更新。"
    case "The /Applications folder is not writable. Update the app manually with an authorized account.": chinese = "/Applications 文件夹不可写，请使用有权限的账户手动更新。"
    case "Cannot create a private update directory in /Applications. Install the app in a writable /Applications folder or update it manually.": chinese = "无法在 /Applications 创建私有更新目录。请使用有写入权限的账户或手动更新。"
    case "Update cancelled. Homebrew installations must be updated through their own brew executable.": chinese = "已取消更新。通过 Homebrew 安装的应用必须使用对应的 brew 更新。"
    case "Could not start the update helper. The installed app was not changed.": chinese = "无法启动更新助手，已安装的应用未被修改。"
    case "The release archive failed its SHA-256 checksum.": chinese = "发行包的 SHA-256 校验失败。"
    case "Invalid SHA256SUMS file.", "SHA256SUMS must contain exactly one valid checksum for the release archive.": chinese = "SHA256SUMS 无效或缺少发行包的唯一校验值。"
    case "The release ZIP has an unsafe or unsupported structure.": chinese = "发行 ZIP 的结构不安全或不受支持，已停止更新。"
    case "The release download redirected to an untrusted location.": chinese = "下载被重定向到不受信任的位置，已停止更新。"
    case "The release download returned an invalid response or is too large.", "The release download exceeds its size limit.": chinese = "下载响应无效或文件超过大小限制。"
    case "The downloaded Community app has the wrong version or executable.", "The release does not contain the expected arm64 Community executable.": chinese = "下载的社区版应用版本或 arm64 可执行文件不正确。"
    case "The downloaded app failed its code-signature integrity check. Ad-hoc signatures do not authenticate its publisher.": chinese = "下载的应用未通过代码签名完整性检查。临时签名不能认证发布者身份。"
    case "Could not preserve the macOS quarantine for the downloaded app; install it manually.": chinese = "无法保留 macOS 隔离标记，请手动安装。"
    case "The selected Homebrew executable is unavailable.": chinese = "所选 Homebrew 可执行文件不可用。"
    case "The selected brew does not have the Torli Stats Cask installed. Choose the Homebrew installation that manages this app.": chinese = "所选 brew 未安装 Torli Stats Cask，请选择管理此应用的 Homebrew。"
    case "The Homebrew Cask checksum does not match the official release checksum. Update manually after the tap is corrected.": chinese = "Homebrew Cask 的校验值与官方发行包不一致。请等待 Tap 修正后手动更新。"
    case "The installed app changed; no update was installed.", "The installed app changed while preparing the update.": chinese = "已安装的应用在更新期间发生变化，未安装更新。"
    case "Could not replace the app; the original remains installed. Check /Applications permissions.": chinese = "无法替换应用，原应用仍在。请检查 /Applications 的权限。"
    case "The new app could not be opened. The original app was restored.": chinese = "无法打开新应用，已恢复原应用。"
    case "The updated app did not start within 30 seconds. macOS may have blocked it or require approval.": chinese = "更新后的应用在 30 秒内未启动。macOS 可能阻止了它或需要您批准。"
    default:
        if message.contains("Homebrew") || message.contains("brew ") {
            chinese = "Homebrew 更新未完成，请检查所选 brew 和 Cask，并按照以下提示操作：\n\(message)"
        } else {
            chinese = "更新未完成，请检查以下错误并在必要时手动更新：\n\(message)"
        }
    }
    return UpdateFailure.message(chinese)
}

private let updateHelperArgument = "--torli-private-update-helper"
private let updateCask = "torli-dev/torli-stats/torli-stats"
private var updateExitDescriptor: Int32 = -1

private func signalUpdateOnNormalExit() {
    guard updateExitDescriptor >= 0 else { return }
    var byte: UInt8 = 1
    _ = Darwin.write(updateExitDescriptor, &byte, 1)
    _ = Darwin.close(updateExitDescriptor)
    updateExitDescriptor = -1
}

enum UpdatePreparationProgress {
    case preparing
    case downloading(received: Int64, total: Int64?)
    case verifying
    case homebrew
}

final class UpdatePreparationTask {
    // Callbacks may cancel their own task, so main-queue delivery is reentrant.
    private let lock = NSRecursiveLock()
    private var cancelled = false
    private var request: URLSessionTask?
    private let progress: (UpdatePreparationProgress) -> Void

    init(progress: @escaping (UpdatePreparationProgress) -> Void = { _ in }) {
        self.progress = progress
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let active = request
        lock.unlock()
        active?.cancel()
    }

    fileprivate func checkCancellation() throws {
        lock.lock()
        defer { lock.unlock() }
        if cancelled { throw URLError(.cancelled) }
    }

    func start(_ request: URLSessionTask) throws {
        lock.lock()
        defer { lock.unlock() }
        if cancelled { throw URLError(.cancelled) }
        self.request = request
        // Registration and resume must be atomic with respect to cancellation.
        request.resume()
    }

    fileprivate func clear(_ request: URLSessionTask) {
        lock.lock()
        defer { lock.unlock() }
        if self.request === request { self.request = nil }
    }

    func report(_ value: UpdatePreparationProgress) {
        DispatchQueue.main.async {
            self.lock.lock()
            defer { self.lock.unlock() }
            guard !self.cancelled else { return }
            self.progress(value)
        }
    }

    func complete<Value>(_ result: Result<Value, Error>, completion: @escaping (Result<Value, Error>) -> Void) {
        DispatchQueue.main.async {
            self.lock.lock()
            defer { self.lock.unlock() }
            completion(self.cancelled ? .failure(URLError(.cancelled)) : result)
        }
    }
}

final class PreparedAppUpdate {
    fileprivate let configuration: UpdateHelperConfiguration
    private let preparation: UpdatePreparationTask
    private var transferred = false

    fileprivate init(configuration: UpdateHelperConfiguration, preparation: UpdatePreparationTask) {
        self.configuration = configuration
        self.preparation = preparation
    }

    deinit {
        if !transferred { try? FileManager.default.removeItem(atPath: configuration.directory) }
    }

    func launchInstaller() throws {
        try preparation.checkCancellation()
        guard updateExitDescriptor == -1 else { throw updateError("An update is already waiting for the app to quit.") }
        let process = Process()
        guard let executable = Bundle.main.executableURL else { throw updateError("Cannot find the running app executable.") }
        process.executableURL = executable
        process.arguments = [updateHelperArgument]
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let encoded = try JSONEncoder().encode(configuration)
        input.fileHandleForWriting.write(encoded + Data([10]))
        // The helper registers for process exit before acknowledging readiness.
        let ready = output.fileHandleForReading.readData(ofLength: 1)
        guard ready == Data([1]) else {
            try? input.fileHandleForWriting.close()
            throw updateError("Could not start the update helper. The installed app was not changed.")
        }
        let duplicate = dup(input.fileHandleForWriting.fileDescriptor)
        guard duplicate >= 0 else { throw updateError("Could not prepare the update exit signal.") }
        guard fcntl(duplicate, F_SETFD, FD_CLOEXEC) == 0 else {
            _ = Darwin.close(duplicate)
            throw updateError("Could not prepare the update exit signal.")
        }
        updateExitDescriptor = duplicate
        try? input.fileHandleForWriting.close()
        transferred = true
        atexit(signalUpdateOnNormalExit)
    }
    func cancelInstaller() {
        if updateExitDescriptor >= 0 {
            _ = Darwin.close(updateExitDescriptor)
            updateExitDescriptor = -1
        }
    }
}

private struct UpdateHelperConfiguration: Codable {
    let parent: Int32
    let target: String
    let directory: String
    let version: String
    let installedVersion: String
    let brew: String?
}

public final class AppUpdateInstaller {
    private let homebrewExecutable: URL?

    init(homebrewExecutable: URL? = nil) {
        self.homebrewExecutable = homebrewExecutable
    }

    @discardableResult
    func prepare(release: AppUpdateRelease, progress: @escaping (UpdatePreparationProgress) -> Void, completion: @escaping (Result<PreparedAppUpdate, Error>) -> Void) -> UpdatePreparationTask {
        let task = UpdatePreparationTask(progress: progress)
        task.report(.preparing)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try Self.prepareUpdate(release, homebrewExecutable: self.homebrewExecutable, task: task) }
            task.complete(result, completion: completion)
        }
        return task
    }

    public static func runHelperIfRequested() -> Bool {
        guard CommandLine.arguments == [CommandLine.arguments[0], updateHelperArgument] else { return false }
        do { try runHelper() }
        catch { showHelperError(error.localizedDescription) }
        return true
    }

    private static func prepareUpdate(_ release: AppUpdateRelease, homebrewExecutable: URL?, task: UpdatePreparationTask) throws -> PreparedAppUpdate {
        try task.checkCancellation()
        let target = try installedApp()
        let version = try validatedVersion(release)
        let installed = try bundleVersion(at: target)
        guard compareVersions(version, installed) == .orderedDescending else {
            throw updateError("The selected release is not newer than the installed app.")
        }
        let fm = FileManager.default
        let directory = target.deletingLastPathComponent().appendingPathComponent(".TorliStats-update-\(UUID().uuidString)", isDirectory: true)
        try task.checkCancellation()
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        } catch {
            throw updateError("Cannot create a private update directory in /Applications. Install the app in a writable /Applications folder or update it manually.")
        }
        do {
            try task.checkCancellation()
            let brew: String?
            if let homebrewExecutable {
                brew = homebrewExecutable.standardizedFileURL.path
                task.report(.homebrew)
                try validateHomebrewCask(brew!)
            } else {
                if let detected = try homebrewForInstalledCask() {
                    brew = detected
                    task.report(.homebrew)
                } else {
                    switch try DispatchQueue.main.sync(execute: {
                        try task.checkCancellation()
                        return chooseInstallationSource()
                    }) {
                    case .manual:
                        brew = nil
                    case let .homebrew(url):
                        brew = url.standardizedFileURL.path
                        try task.checkCancellation()
                        task.report(.homebrew)
                        try validateHomebrewCask(brew!)
                    case .cancel:
                        throw updateError("Update cancelled. Homebrew installations must be updated through their own brew executable.")
                    }
                }
            }
            try task.checkCancellation()
            if let brew {
                try prepareHomebrew(brew, version: version, task: task)
                try task.checkCancellation()
                // Keep a private copy in case Homebrew removes the app before failing.
                try runCommand("/usr/bin/ditto", [target.path, directory.appendingPathComponent("TorliStats.app").path])
            } else {
                let archiveName = "TorliStats-\(version)-macos-arm64.zip"
                let base = "https://github.com/JamesLi-dev/torli-stats/releases/download/v\(version)/"
                let sums = try UpdateDownload.get(URL(string: base + "SHA256SUMS")!, limit: 256 * 1024, task: task)
                let archive = try UpdateDownload.get(URL(string: base + archiveName)!, limit: 128 * 1024 * 1024, task: task, reportProgress: true)
                try task.checkCancellation()
                task.report(.verifying)
                try verifyChecksum(sums: sums, archive: archive, name: archiveName)
                try task.checkCancellation()
                try validateArchive(archive)
                try task.checkCancellation()
                let zip = directory.appendingPathComponent("release.zip")
                try archive.write(to: zip, options: .atomic)
                try task.checkCancellation()
                try runCommand("/usr/bin/ditto", ["-x", "-k", zip.path, directory.path])
                try fm.removeItem(at: zip)
                try task.checkCancellation()
                try validateExtractedTree(directory.appendingPathComponent("TorliStats.app"))
                try task.checkCancellation()
                try validateBundle(directory.appendingPathComponent("TorliStats.app"), version: version)
                try task.checkCancellation()
                try quarantine(directory.appendingPathComponent("TorliStats.app"))
            }
            try task.checkCancellation()
            return PreparedAppUpdate(configuration: UpdateHelperConfiguration(parent: getpid(), target: target.path, directory: directory.path, version: version, installedVersion: installed, brew: brew), preparation: task)
        } catch {
            try? fm.removeItem(at: directory)
            throw error
        }
    }
}

func validatedVersion(_ release: AppUpdateRelease) throws -> String {
    let value = release.version
    let parts = value.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.count <= 9 && $0.allSatisfy(\.isNumber) && ($0.count == 1 || $0.first != "0") && $0.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) }),
          let url = URLComponents(url: release.downloadURL, resolvingAgainstBaseURL: false), url.scheme == "https", url.host == "github.com", url.port == nil, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
          url.percentEncodedPath == "/JamesLi-dev/torli-stats/releases/tag/v\(value)" else {
        throw updateError("The release does not have a trusted GitHub semantic-version tag.")
    }
    return value
}

private func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
    let a = lhs.split(separator: ".").compactMap { Int($0) }
    let b = rhs.split(separator: ".").compactMap { Int($0) }
    guard a.count == 3, b.count == 3 else { return .orderedSame }
    for i in 0..<3 { if a[i] != b[i] { return a[i] < b[i] ? .orderedAscending : .orderedDescending } }
    return .orderedSame
}

private func bundleVersion(at url: URL) throws -> String {
    let data = try Data(contentsOf: url.appendingPathComponent("Contents/Info.plist"))
    guard let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          info["CFBundleIdentifier"] as? String == "local.torli.stats",
          info["CFBundleExecutable"] as? String == "TorliStats",
          info["TorliUpdateChecksDisabled"] as? Bool != true,
          let version = info["CFBundleShortVersionString"] as? String,
          version.split(separator: ".").count == 3,
          version.split(separator: ".").allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { $0 >= 48 && $0 <= 57 } }) else {
        throw updateError("This is not a valid Community app; Pro and unrecognized bundles cannot be replaced.")
    }
    return version
}

private func installedApp() throws -> URL {
    let target = Bundle.main.bundleURL.standardizedFileURL
    guard target.path == "/Applications/TorliStats.app", target.resolvingSymlinksInPath().path == target.path,
          Bundle.main.executableURL?.standardizedFileURL.path == target.appendingPathComponent("Contents/MacOS/TorliStats").path else {
        throw updateError("Only the installed Community app at /Applications/TorliStats.app can be updated. Development, temporary, renamed and symlinked copies must be updated manually.")
    }
    _ = try bundleVersion(at: target)
    guard FileManager.default.isWritableFile(atPath: "/Applications") else {
        throw updateError("The /Applications folder is not writable. Update the app manually with an authorized account.")
    }
    return target
}

private func validateBundle(_ url: URL, version: String) throws {
    guard try bundleVersion(at: url) == version,
          FileManager.default.isExecutableFile(atPath: url.appendingPathComponent("Contents/MacOS/TorliStats").path) else {
        throw updateError("The downloaded Community app has the wrong version or executable.")
    }
    let executable = try FileHandle(forReadingFrom: url.appendingPathComponent("Contents/MacOS/TorliStats"))
    defer { try? executable.close() }
    guard try executable.read(upToCount: 8) == Data([0xcf, 0xfa, 0xed, 0xfe, 0x0c, 0x00, 0x00, 0x01]) else {
        throw updateError("The release does not contain the expected arm64 Community executable.")
    }
    do { try runCommand("/usr/bin/codesign", ["--verify", "--deep", "--strict", url.path]) }
    catch { throw updateError("The downloaded app failed its code-signature integrity check. Ad-hoc signatures do not authenticate its publisher.") }
}

private func runCommand(_ executable: String, _ arguments: [String], environment: [String: String]? = nil) throws {
    let timeout: TimeInterval = executable.hasSuffix("/brew") ? 600 : 120
    _ = try executeUpdateCommand(executable, arguments, environment: environment, timeout: timeout)
}

// Bash job control starts the command in its own process group. On timeout the
// wrapper kills that entire group before reporting failure, so an ordinary brew
// child cannot continue modifying the installation while recovery runs.
func executeUpdateCommand(_ executable: String, _ arguments: [String], environment: [String: String]? = nil, timeout: TimeInterval, capture: Bool = false) throws -> Data {
    let process = Process()
    let completion = DispatchSemaphore(value: 0)
    let script = """
    set -m
    if [ "$1" = capture ]; then ulimit -f 16384 || exit 125; fi
    shift
    child=
    trap 'if [ -n "$child" ]; then kill -TERM -- "-$child" 2>/dev/null; /bin/sleep 1; kill -KILL -- "-$child" 2>/dev/null; wait "$child" 2>/dev/null; fi; exit 124' TERM INT
    "$@" &
    child=$!
    wait "$child"
    exit $?
    """
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = ["-c", script, "torli-update", capture ? "capture" : "discard", executable] + arguments
    process.standardInput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    if let environment { process.environment = environment }
    var output: FileHandle?
    var temporaryPath: String?
    if capture {
        var template = Array((NSTemporaryDirectory() + "torli-update-output-XXXXXX").utf8CString)
        let fd = mkstemp(&template)
        guard fd >= 0 else { throw updateError("Could not create a private command output file.") }
        temporaryPath = String(cString: template)
        output = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        process.standardOutput = output
    } else {
        process.standardOutput = FileHandle.nullDevice
    }
    defer {
        try? output?.close()
        if let temporaryPath { unlink(temporaryPath) }
    }
    process.terminationHandler = { _ in completion.signal() }
    try process.run()
    guard completion.wait(timeout: .now() + timeout) == .success else {
        _ = kill(process.processIdentifier, SIGTERM)
        if completion.wait(timeout: .now() + 5) != .success {
            _ = kill(process.processIdentifier, SIGKILL)
            _ = completion.wait(timeout: .now() + 1)
        }
        throw updateError("Command timed out: \(executable).")
    }
    guard process.terminationReason == .exit, process.terminationStatus == 0 else { throw updateError("Command failed: \(executable).") }
    guard let output else { return Data() }
    try output.seek(toOffset: 0)
    let data = try output.read(upToCount: 1_048_577) ?? Data()
    guard data.count <= 1_048_576 else { throw updateError("Command output exceeded the size limit.") }
    return data
}

private func homebrewForInstalledCask() throws -> String? {
    var prefixes = ["/opt/homebrew", "/usr/local"]
    if let prefix = ProcessInfo.processInfo.environment["HOMEBREW_PREFIX"], prefix.hasPrefix("/") { prefixes.append(prefix) }
    if let cellar = ProcessInfo.processInfo.environment["HOMEBREW_CASKROOM"], cellar.hasPrefix("/"), FileManager.default.fileExists(atPath: cellar + "/torli-stats") {
        guard let prefix = ProcessInfo.processInfo.environment["HOMEBREW_PREFIX"] else { throw updateError("Homebrew manages this app, but its executable could not be identified. Run brew upgrade --cask \(updateCask).") }
        let brew = prefix + "/bin/brew"
        guard FileManager.default.isExecutableFile(atPath: brew) else { throw updateError("Homebrew manages this app but brew is unavailable. Run brew upgrade --cask \(updateCask).") }
        return brew
    }
    for prefix in prefixes where FileManager.default.fileExists(atPath: prefix + "/Caskroom/torli-stats") {
        let brew = prefix + "/bin/brew"
        guard FileManager.default.isExecutableFile(atPath: brew) else { throw updateError("Homebrew manages this app but brew is unavailable. Run brew upgrade --cask \(updateCask).") }
        return brew
    }
    return nil
}

private func prepareHomebrew(_ brew: String, version: String, task: UpdatePreparationTask) throws {
    var environment = ProcessInfo.processInfo.environment
    environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
    environment["HOMEBREW_NO_INSTALL_CLEANUP"] = "1"
    environment["HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK"] = "1"
    environment["NONINTERACTIVE"] = "1"
    try task.checkCancellation()
    do { try runCommand(brew, ["update"], environment: environment) }
    catch { throw updateError("Homebrew could not refresh its tap. Run brew update and brew upgrade --cask \(updateCask) in Terminal.") }
    try task.checkCancellation()
    let data = try executeUpdateCommand(brew, ["info", "--cask", "--json=v2", updateCask], environment: environment, timeout: 60, capture: true)
    try task.checkCancellation()
    let archiveName = "TorliStats-\(version)-macos-arm64.zip"
    let base = "https://github.com/JamesLi-dev/torli-stats/releases/download/v\(version)/"
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let casks = root["casks"] as? [[String: Any]], casks.count == 1,
          casks[0]["version"] as? String == version,
          casks[0]["url"] as? String == base + archiveName,
          let caskHash = casks[0]["sha256"] as? String,
          let installed = casks[0]["installed"] as? String, !installed.isEmpty else {
        throw updateError("The Homebrew tap has not published this version yet, or this Cask is not installed. Try again later or run brew update && brew upgrade --cask \(updateCask).")
    }
    let sums = try UpdateDownload.get(URL(string: base + "SHA256SUMS")!, limit: 256 * 1024, task: task)
    guard try checksum(sums: sums, name: archiveName) == caskHash.lowercased() else {
        throw updateError("The Homebrew Cask checksum does not match the official release checksum. Update manually after the tap is corrected.")
    }
}

func verifyChecksum(sums: Data, archive: Data, name: String) throws {
    let expected = try checksum(sums: sums, name: name)
    let actual = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
    guard actual == expected else { throw updateError("The release archive failed its SHA-256 checksum.") }
}

private func checksum(sums: Data, name: String) throws -> String {
    guard let text = String(data: sums, encoding: .utf8) else { throw updateError("Invalid SHA256SUMS file.") }
    var matches: [String] = []
    for line in text.split(whereSeparator: \.isNewline) {
        let fields = line.split(separator: " ", omittingEmptySubsequences: true)
        if fields.count == 2 && (fields[1] == name || fields[1] == "*" + name) { matches.append(String(fields[0])) }
    }
    guard matches.count == 1, matches[0].count == 64,
          matches[0].utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) || (65...70).contains($0) }) else {
        throw updateError("SHA256SUMS must contain exactly one valid checksum for the release archive.")
    }
    return matches[0].lowercased()
}

final class UpdateDownload: NSObject, URLSessionDataDelegate {
    private let limit: Int
    private let preparation: UpdatePreparationTask
    private let reportProgress: Bool
    private var data = Data()
    private var expectedLength: Int64?
    private var lastProgressTime: TimeInterval = 0
    private var lastReportedBytes: Int64 = -1
    private var lastReportedTotal: Int64?
    private var failure: Error?
    private let done = DispatchSemaphore(value: 0)

    private init(limit: Int, preparation: UpdatePreparationTask, reportProgress: Bool) {
        self.limit = limit
        self.preparation = preparation
        self.reportProgress = reportProgress
    }

    static func get(_ url: URL, limit: Int, task: UpdatePreparationTask, reportProgress: Bool = false, configuration: URLSessionConfiguration = .ephemeral) throws -> Data {
        try task.checkCancellation()
        let delegate = UpdateDownload(limit: limit, preparation: task, reportProgress: reportProgress)
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        let request = session.dataTask(with: url)
        defer {
            task.clear(request)
            session.invalidateAndCancel()
        }
        try task.start(request)
        delegate.done.wait()
        try task.checkCancellation()
        if let failure = delegate.failure { throw failure }
        return delegate.data
    }

    private func reportDownloadProgress(force: Bool = false) {
        guard reportProgress else { return }
        let received = Int64(data.count)
        let now = ProcessInfo.processInfo.systemUptime
        guard force || now - lastProgressTime >= 0.1 else { return }
        guard received != lastReportedBytes || expectedLength != lastReportedTotal else { return }
        lastProgressTime = now
        lastReportedBytes = received
        lastReportedTotal = expectedLength
        preparation.report(.downloading(received: received, total: expectedLength))
    }

    private func allowed(_ url: URL) -> Bool {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false), c.scheme == "https", c.port == nil || c.port == 443, c.user == nil, c.password == nil else { return false }
        if c.host == "github.com" { return c.path.hasPrefix("/JamesLi-dev/torli-stats/releases/download/") }
        return c.host == "release-assets.githubusercontent.com" || c.host == "objects.githubusercontent.com"
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, allowed(url) else { failure = updateError("The release download redirected to an untrusted location."); completionHandler(nil); return }
        completionHandler(request)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse, response.statusCode == 200, let url = response.url, allowed(url), response.expectedContentLength <= Int64(limit) else {
            failure = updateError("The release download returned an invalid response or is too large.")
            completionHandler(.cancel); return
        }
        let encoded = response.value(forHTTPHeaderField: "Content-Encoding")?.lowercased()
        let expected = response.expectedContentLength
        expectedLength = expected > 0 && (encoded == nil || encoded == "identity") ? expected : nil
        reportDownloadProgress(force: true)
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        guard chunk.count <= limit - data.count else { failure = updateError("The release download exceeds its size limit."); dataTask.cancel(); return }
        data.append(chunk)
        if let expectedLength, Int64(data.count) > expectedLength { self.expectedLength = nil }
        reportDownloadProgress()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if failure == nil, let error { failure = error }
        if failure == nil {
            if let expectedLength, expectedLength != Int64(data.count) { self.expectedLength = nil }
            reportDownloadProgress(force: true)
        }
        done.signal()
    }
}

// Inspect central and local ZIP records before asking ditto to extract anything.
// ZIP64, encrypted entries, links, duplicate paths and special files are rejected.
func validateArchive(_ data: Data) throws {
    func bad() -> Error { updateError("The release ZIP has an unsafe or unsupported structure.") }
    func u16(_ offset: Int) throws -> Int {
        guard offset >= 0, offset <= data.count - 2 else { throw bad() }
        return Int(data[offset]) | Int(data[offset + 1]) << 8
    }
    func u32(_ offset: Int) throws -> Int {
        guard offset >= 0, offset <= data.count - 4 else { throw bad() }
        return Int(data[offset]) | Int(data[offset + 1]) << 8 | Int(data[offset + 2]) << 16 | Int(data[offset + 3]) << 24
    }
    func checkExtra(_ start: Int, _ length: Int) throws {
        let end = start + length
        var cursor = start
        while cursor < end {
            guard cursor <= end - 4 else { throw bad() }
            let kind = try u16(cursor)
            let size = try u16(cursor + 2)
            guard size <= end - cursor - 4, ![0x0001, 0x000d, 0x334d, 0x7075, 0x756e].contains(kind) else { throw bad() }
            cursor += 4 + size
        }
    }
    guard data.count >= 22 else { throw bad() }
    var end: Int?
    for offset in stride(from: data.count - 22, through: max(0, data.count - 65557), by: -1) {
        if try u32(offset) == 0x06054b50, offset + 22 + (try u16(offset + 20)) == data.count {
            end = offset
            break
        }
    }
    guard let end, try u16(end + 4) == 0, try u16(end + 6) == 0 else { throw bad() }
    let count = try u16(end + 10)
    let centralSize = try u32(end + 12)
    let centralStart = try u32(end + 16)
    guard count > 0, count <= 20_000, try u16(end + 8) == count,
          centralStart <= end, centralSize == end - centralStart else { throw bad() }
    var offset = centralStart
    var total = 0
    var paths = Set<String>()
    var ranges: [Range<Int>] = []
    var hasApp = false
    for _ in 0..<count {
        guard try u32(offset) == 0x02014b50, offset <= end - 46 else { throw bad() }
        let madeBy = try u16(offset + 4)
        let flags = try u16(offset + 8)
        let method = try u16(offset + 10)
        let compressed = try u32(offset + 20)
        let expanded = try u32(offset + 24)
        let nameLength = try u16(offset + 28)
        let extraLength = try u16(offset + 30)
        let commentLength = try u16(offset + 32)
        let attributes = try u32(offset + 38)
        let local = try u32(offset + 42)
        let entryEnd = offset + 46 + nameLength + extraLength + commentLength
        guard entryEnd <= end, nameLength > 0, nameLength <= 1024,
              flags & 0x41 == 0, method == 0 || method == 8,
              compressed != 0xffffffff, expanded != 0xffffffff, local != 0xffffffff,
              expanded <= 256 * 1024 * 1024, total <= 512 * 1024 * 1024 - expanded,
              expanded <= max(1_048_576, compressed * 1000),
              let name = String(data: data.subdata(in: offset + 46..<offset + 46 + nameLength), encoding: .utf8),
              !name.hasPrefix("/"), !name.contains("\\"), !name.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else { throw bad() }
        try checkExtra(offset + 46 + nameLength, extraLength)
        total += expanded
        let directory = name.hasSuffix("/")
        let components = name.split(separator: "/", omittingEmptySubsequences: false)
        guard components.first == "TorliStats.app" || (components.first == "__MACOSX" && components.count > 1 && components[1] == "TorliStats.app"),
              !components.dropLast(directory ? 1 : 0).contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
              paths.insert(name.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased().precomposedStringWithCanonicalMapping).inserted else { throw bad() }
        if components.first == "TorliStats.app" { hasApp = true }
        guard (!directory || expanded == 0), method != 0 || compressed == expanded else { throw bad() }
        if madeBy >> 8 == 3 {
            let type = (attributes >> 16) & 0o170000
            guard type == 0 || type == 0o100000 || (type == 0o040000 && directory) else { throw bad() }
        }
        guard try u32(local) == 0x04034b50, local <= centralStart - 30,
              try u16(local + 6) == flags, try u16(local + 8) == method else { throw bad() }
        let localNameLength = try u16(local + 26)
        let localExtraLength = try u16(local + 28)
        let start = local + 30 + localNameLength + localExtraLength
        guard localNameLength == nameLength, start <= centralStart, compressed <= centralStart - start,
              data.subdata(in: local + 30..<local + 30 + localNameLength) == data.subdata(in: offset + 46..<offset + 46 + nameLength) else { throw bad() }
        try checkExtra(local + 30 + localNameLength, localExtraLength)
        var recordEnd = start + compressed
        if flags & 8 == 0 {
            guard try u32(local + 14) == u32(offset + 16),
                  try u32(local + 18) == compressed, try u32(local + 22) == expanded else { throw bad() }
        } else {
            let localCompressed = try u32(local + 18)
            let localExpanded = try u32(local + 22)
            guard (localCompressed == 0 || localCompressed == compressed),
                  (localExpanded == 0 || localExpanded == expanded),
                  recordEnd <= centralStart - 12 else { throw bad() }
            if try u32(recordEnd) == 0x08074b50 { recordEnd += 4 }
            guard recordEnd <= centralStart - 12,
                  try u32(recordEnd) == u32(offset + 16),
                  try u32(recordEnd + 4) == compressed,
                  try u32(recordEnd + 8) == expanded else { throw bad() }
            recordEnd += 12
        }
        ranges.append(local..<recordEnd)
        offset = entryEnd
    }
    guard offset == end, hasApp else { throw bad() }
    ranges.sort { $0.lowerBound < $1.lowerBound }
    for i in 1..<ranges.count where ranges[i - 1].upperBound > ranges[i].lowerBound { throw bad() }
}

private func validateExtractedTree(_ root: URL) throws {
    let fm = FileManager.default
    var enumerationError: Error?
    guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey], options: [], errorHandler: { _, error in enumerationError = error; return false }) else {
        throw updateError("Cannot inspect the extracted app.")
    }
    var count = 0
    var total: Int64 = 0
    for case let url as URL in enumerator {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isSymbolicLink != true, values.isRegularFile == true || values.isDirectory == true else { throw updateError("The extracted app contains an unsafe file.") }
        count += 1
        total += Int64(values.fileSize ?? 0)
        guard count <= 20_000, total <= 512 * 1024 * 1024 else { throw updateError("The extracted app is too large.") }
    }
    if let enumerationError { throw enumerationError }
}

private func quarantine(_ app: URL) throws {
    let stamp = String(Int(Date().timeIntervalSince1970), radix: 16)
    let value = "0081;\(stamp);TorliStats;\(UUID().uuidString)"
    let urls = [app] + ((FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil)?.allObjects as? [URL]) ?? [])
    for url in urls {
        let result = value.withCString { valuePointer in
            url.path.withCString { path in
                setxattr(path, "com.apple.quarantine", valuePointer, strlen(valuePointer), 0, 0)
            }
        }
        guard result == 0 else { throw updateError("Could not preserve the macOS quarantine for the downloaded app; install it manually.") }
    }
}

@_silgen_name("proc_pidpath") private func updateProcPath(_ pid: Int32, _ buffer: UnsafeMutableRawPointer, _ size: UInt32) -> Int32

private func runHelper() throws {
    let input = FileHandle.standardInput
    var line = Data()
    while line.count < 16_384 {
        let byte = input.readData(ofLength: 1)
        guard byte.count == 1 else { return }
        if byte[0] == 10 { break }
        line.append(byte)
    }
    let config = try JSONDecoder().decode(UpdateHelperConfiguration.self, from: line)
    let target = URL(fileURLWithPath: config.target).standardizedFileURL
    let directory = URL(fileURLWithPath: config.directory).standardizedFileURL
    let candidate = directory.appendingPathComponent("TorliStats.app")
    guard config.parent == getppid(), target.path == "/Applications/TorliStats.app",
          Bundle.main.bundleURL.standardizedFileURL.path == target.path,
          target.resolvingSymlinksInPath().path == target.path,
          directory.deletingLastPathComponent().path == "/Applications",
          directory.lastPathComponent.hasPrefix(".TorliStats-update-"),
          UUID(uuidString: String(directory.lastPathComponent.dropFirst(".TorliStats-update-".count))) != nil,
          directory.resolvingSymlinksInPath().path == directory.path else { throw updateError("Invalid update helper request.") }
    var info = stat()
    guard lstat(directory.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR,
          info.st_uid == getuid(), (info.st_mode & 0o777) == 0o700 else { throw updateError("The update staging directory is not private.") }
    var parentPath = [CChar](repeating: 0, count: 4096)
    guard updateProcPath(config.parent, &parentPath, UInt32(parentPath.count)) > 0,
          String(cString: parentPath) == target.appendingPathComponent("Contents/MacOS/TorliStats").path,
          try bundleVersion(at: target) == config.installedVersion else { throw updateError("The installed app changed while preparing the update.") }
    if config.brew == nil { try validateBundle(candidate, version: config.version) }
    var preserveDirectory = false
    defer { if !preserveDirectory { try? FileManager.default.removeItem(at: directory) } }
    let queue = kqueue()
    guard queue >= 0 else { throw updateError("Cannot monitor the app's exit.") }
    defer { _ = close(queue) }
    var event = kevent()
    event.ident = UInt(config.parent)
    event.filter = Int16(EVFILT_PROC)
    event.flags = UInt16(EV_ADD | EV_ONESHOT)
    event.fflags = UInt32(NOTE_EXIT)
    guard kevent(queue, &event, 1, nil, 0, nil) == 0 else { throw updateError("Cannot monitor the app's exit.") }
    FileHandle.standardOutput.write(Data([1]))
    guard input.readData(ofLength: 1) == Data([1]) else { return }
    var occurred = kevent()
    guard kevent(queue, nil, 0, &occurred, 1, nil) == 1 else { throw updateError("Could not confirm the app exited; no update was installed.") }
    do {
        guard try bundleVersion(at: target) == config.installedVersion else { throw updateError("The installed app changed; no update was installed.") }
        if let brew = config.brew {
            try performHomebrewUpdate(brew, target: target, backup: candidate, version: config.version, installedVersion: config.installedVersion)
        } else {
            guard try homebrewForInstalledCask() == nil else { throw updateError("Homebrew now manages this app; update it with brew upgrade --cask \(updateCask).") }
            try validateBundle(candidate, version: config.version)
            try swapAndLaunch(target: target, replacement: candidate) { try openAndConfirm(target) }
        }
    } catch {
        if error is UpdateRollbackFailure || error is HomebrewRecoveryFailure { preserveDirectory = true }
        try? runCommand("/usr/bin/open", ["-n", target.path])
        throw error
    }
}

private struct UpdateRollbackFailure: LocalizedError {
    let path: String
    var errorDescription: String? { updateText("The new app could not be opened and automatic rollback failed. The previous app remains in \(path); restore it manually before deleting that folder.", "无法打开新应用且自动回滚失败。旧应用保存在 \(path)，删除该目录前请手动恢复。") }
}

private struct HomebrewRecoveryFailure: LocalizedError {
    let path: String
    let cause: String
    let restored: Bool
    var errorDescription: String? {
        if updateUsesChinese {
            let status = restored ? "已尽力恢复旧应用。" : "无法自动恢复旧应用；请勿覆盖无法识别的应用或 Pro。"
            return "Homebrew 未能完成更新。\(status) 旧应用备份保存在 \(path)。Homebrew 记录可能不一致；请在终端运行 brew update && brew reinstall --cask \(updateCask)。\(cause)"
        }
        let status = restored ? "The previous app was restored when possible." : "The previous app could not be restored automatically; do not overwrite an unrecognized or Pro app."
        return "Homebrew could not complete the update. \(status) A copy of the previous app remains at \(path). Homebrew records may not match; run brew update && brew reinstall --cask \(updateCask) in Terminal. \(cause)"
    }
}

// The replacement and original are siblings on one filesystem. Swap is a
// single filesystem operation; if launch fails, swap back before reporting it.
func swapAndLaunch(target: URL, replacement: URL, launch: () throws -> Void) throws {
    guard renamex_np(target.path, replacement.path, UInt32(RENAME_SWAP)) == 0 else {
        throw updateError("Could not replace the app; the original remains installed. Check /Applications permissions.")
    }
    do { try launch() }
    catch {
        guard renamex_np(target.path, replacement.path, UInt32(RENAME_SWAP)) == 0 else {
            throw UpdateRollbackFailure(path: replacement.path)
        }
        throw updateError("The new app could not be opened. The original app was restored.")
    }
}

private func performHomebrewUpdate(_ brew: String, target: URL, backup: URL, version: String, installedVersion: String) throws {
    try validateHomebrewCask(brew)
    var environment = ProcessInfo.processInfo.environment
    environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
    environment["HOMEBREW_NO_INSTALL_CLEANUP"] = "1"
    environment["HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK"] = "1"
    environment["NONINTERACTIVE"] = "1"
    do {
        try runCommand(brew, ["upgrade", "--cask", updateCask], environment: environment)
        guard try bundleVersion(at: target) == version else { throw updateError("Homebrew did not install the selected version.") }
        try openAndConfirm(target)
    } catch {
        let originalError = error
        let restored = (try? recoverHomebrewApp(target: target, backup: backup, newVersion: version, oldVersion: installedVersion)) ?? false
        throw HomebrewRecoveryFailure(path: backup.path, cause: originalError.localizedDescription, restored: restored)
    }
}

private func showHelperError(_ message: String) {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = updateText("Torli Stats update could not be completed", "Torli Stats 更新未完成")
    alert.informativeText = message
    alert.addButton(withTitle: updateText("OK", "好"))
    alert.runModal()
}

private enum UpdateInstallSource {
    case manual
    case homebrew(URL)
    case cancel
}

private func chooseInstallationSource() -> UpdateInstallSource {
    let alert = NSAlert()
    alert.messageText = updateText("How was Torli Stats installed?", "Torli Stats 是如何安装的？")
    alert.informativeText = updateText("No Homebrew receipt was found in the usual locations. Custom Homebrew installations cannot always be detected. Choose the actual installation method; a Homebrew installation must be updated by its own brew.", "未在常见位置找到 Homebrew 记录，无法自动识别所有自定义 Homebrew 安装。请选择实际安装方式；Homebrew 安装必须使用对应的 brew 更新。")
    alert.addButton(withTitle: updateText("Official manual download", "官网下载并手动安装"))
    alert.addButton(withTitle: updateText("Homebrew", "Homebrew"))
    alert.addButton(withTitle: updateText("Cancel", "取消"))
    switch alert.runModal() {
    case .alertFirstButtonReturn:
        return .manual
    case .alertSecondButtonReturn:
        let panel = NSOpenPanel()
        panel.message = updateText("Select the brew executable that manages this installation.", "请选择管理此应用的 brew 可执行文件。")
        panel.prompt = updateText("Choose brew", "选择 brew")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return .cancel }
        return .homebrew(url)
    default:
        return .cancel
    }
}

private func validateHomebrewCask(_ brew: String) throws {
    guard brew.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: brew) else {
        throw updateError("The selected Homebrew executable is unavailable.")
    }
    var environment = ProcessInfo.processInfo.environment
    environment["NONINTERACTIVE"] = "1"
    environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
    let data = try executeUpdateCommand(brew, ["--caskroom"], environment: environment, timeout: 30, capture: true)
    guard data.count <= 4096,
          let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
          path.hasPrefix("/"), FileManager.default.fileExists(atPath: URL(fileURLWithPath: path).appendingPathComponent("torli-stats").path) else {
        throw updateError("The selected brew does not have the Torli Stats Cask installed. Choose the Homebrew installation that manages this app.")
    }
}

private func openAndConfirm(_ target: URL) throws {
    let started = Date()
    try runCommand("/usr/bin/open", ["-n", target.path])
    let deadline = Date().addingTimeInterval(30)
    var previous: pid_t?
    var consecutive = 0
    while Date() < deadline {
        let app = NSRunningApplication.runningApplications(withBundleIdentifier: "local.torli.stats").first { app in
            guard app.processIdentifier != getpid(), !app.isTerminated,
                  app.bundleURL?.standardizedFileURL.path == target.path,
                  let date = app.launchDate, date >= started.addingTimeInterval(-2) else { return false }
            var path = [CChar](repeating: 0, count: 4096)
            return updateProcPath(app.processIdentifier, &path, UInt32(path.count)) > 0 &&
                String(cString: path) == target.appendingPathComponent("Contents/MacOS/TorliStats").path
        }
        if let pid = app?.processIdentifier {
            consecutive = previous == pid ? consecutive + 1 : 1
            previous = pid
            if consecutive >= 3 { return }
        } else {
            previous = nil
            consecutive = 0
        }
        Thread.sleep(forTimeInterval: 1)
    }
    throw updateError("The updated app did not start within 30 seconds. macOS may have blocked it or require approval.")
}

// Keep the original backup even if Homebrew changed its receipt. Only replace
// a recognized Community bundle of the version just installed, never Pro or an
// unrelated app that appeared concurrently.
func recoverHomebrewApp(target: URL, backup: URL, newVersion: String, oldVersion: String) throws -> Bool {
    guard try bundleVersion(at: backup) == oldVersion else { return false }
    let fm = FileManager.default
    let exists = fm.fileExists(atPath: target.path)
    if exists {
        // Only the app itself must be a real directory here. Its parent may
        // legitimately contain system aliases (for example /var -> /private/var).
        // Production callers separately require the canonical /Applications path.
        var info = stat()
        guard lstat(target.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else { return false }
        let current = try bundleVersion(at: target)
        guard current == oldVersion || current == newVersion else { return false }
    }
    let recovery = backup.deletingLastPathComponent().appendingPathComponent("Recovery-TorliStats.app")
    defer { try? fm.removeItem(at: recovery) }
    try runCommand("/usr/bin/ditto", [backup.path, recovery.path])
    let flags = exists ? UInt32(RENAME_SWAP) : UInt32(RENAME_EXCL)
    return renamex_np(recovery.path, target.path, flags) == 0
}
