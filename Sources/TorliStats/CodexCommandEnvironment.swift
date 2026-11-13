import Foundation

/// Finder does not inherit interactive shell setup. Discover conventional CLI
/// locations directly; never run shell startup files while rendering settings.
struct CodexCommandEnvironment {
    let inherited: [String: String]
    let userHome: URL
    let systemPaths: [String]

    init(
        inherited: [String: String] = ProcessInfo.processInfo.environment,
        userHome: URL = FileManager.default.homeDirectoryForCurrentUser,
        systemPaths: [String] = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
    ) {
        self.inherited = inherited
        self.userHome = userHome
        self.systemPaths = systemPaths
    }

    func executableURL() -> URL? {
        searchPaths.lazy.map { URL(fileURLWithPath: $0).appendingPathComponent("codex") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    func environment(executable: URL, codexHome: URL) -> [String: String] {
        // Preserve proxies, certificate settings, locale, and other inherited
        // values. Only CODEX_HOME selects the account; HOME remains the user.
        var environment = inherited
        var paths = [executable.deletingLastPathComponent().path]
        if let nodeDirectory = nodeDirectory(for: executable) { paths.append(nodeDirectory) }
        paths += searchPaths
        environment["PATH"] = uniqueAbsolutePaths(paths).joined(separator: ":")
        if environment["HOME"]?.isEmpty != false { environment["HOME"] = userHome.path }
        environment["CODEX_HOME"] = codexHome.path
        return environment
    }

    private var searchPaths: [String] {
        var paths = (inherited["PATH"] ?? "").split(separator: ":").map(String.init)
        if let bin = inherited["NVM_BIN"] { paths.append(expanded(bin)) }
        for key in ["VOLTA_HOME", "BUN_INSTALL", "NPM_CONFIG_PREFIX", "npm_config_prefix"] {
            if let prefix = inherited[key], !prefix.isEmpty {
                paths.append(expanded(prefix) + "/bin")
            }
        }
        if let prefix = npmPrefix { paths.append(prefix + "/bin") }
        paths += [".local/bin", ".npm-global/bin", ".npm/bin", ".bun/bin", ".volta/bin",
                  ".nvm/current/bin", ".local/share/fnm/aliases/default/bin",
                  "Library/Application Support/fnm/aliases/default/bin"].map {
            userHome.appendingPathComponent($0).path
        }
        paths += systemPaths
        paths += nvmPaths
        return uniqueAbsolutePaths(paths)
    }

    private var npmPrefix: String? {
        let file = userHome.appendingPathComponent(".npmrc")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        var prefix: String?
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "prefix" else { continue }
            let value = parts[1].trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !value.isEmpty { prefix = expanded(value) }
        }
        return prefix
    }

    private var nvmPaths: [String] {
        let root = URL(fileURLWithPath: expanded(inherited["NVM_DIR"] ?? "~/.nvm"))
        let versions = root.appendingPathComponent("versions/node", isDirectory: true)
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: versions.path)) ?? [])
            .filter { $0.range(of: "^v[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression) != nil }
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
        // Prefer the configured default (including aliases such as lts/*),
        // falling back to other installed versions if that CLI is absent.
        let preferred = nvmDefault(in: root)
        let ordered = names.filter { matchesNVMVersion($0, preferred) }
            + names.filter { !matchesNVMVersion($0, preferred) }
        return ordered.map { versions.appendingPathComponent($0).appendingPathComponent("bin").path }
    }

    private func nvmDefault(in root: URL) -> String? {
        var alias = "default"
        var visited = Set<String>()
        for _ in 0..<5 {
            guard !alias.hasPrefix("/"), !alias.split(separator: "/").contains(".."),
                  visited.insert(alias).inserted,
                  let value = try? String(contentsOf: root.appendingPathComponent("alias/" + alias), encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return alias }
            alias = value
        }
        return nil
    }

    private func matchesNVMVersion(_ version: String, _ preferred: String?) -> Bool {
        guard let preferred else { return false }
        let prefix = preferred.hasPrefix("v") ? preferred : "v" + preferred
        return version == prefix || version.hasPrefix(prefix + ".")
    }

    /// npm's codex shim can be symlinked out of an nvm install. Keep its node
    /// runtime ahead of unrelated versions, even when the inherited PATH is short.
    private func nodeDirectory(for executable: URL) -> String? {
        let direct = executable.deletingLastPathComponent()
        if FileManager.default.isExecutableFile(atPath: direct.appendingPathComponent("node").path) {
            return direct.path
        }
        var directory = executable.resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<8 {
            let bin = directory.appendingPathComponent("bin")
            if FileManager.default.isExecutableFile(atPath: bin.appendingPathComponent("node").path) {
                return bin.path
            }
            let parent = directory.deletingLastPathComponent()
            if parent == directory { break }
            directory = parent
        }
        return nil
    }

    private func expanded(_ path: String) -> String {
        let path = path.replacingOccurrences(of: "${HOME}", with: userHome.path)
        if path == "~" { return userHome.path }
        if path.hasPrefix("~/") { return userHome.appendingPathComponent(String(path.dropFirst(2))).path }
        return path
    }

    private func uniqueAbsolutePaths(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.filter { $0.hasPrefix("/") && seen.insert($0).inserted }
    }
}
