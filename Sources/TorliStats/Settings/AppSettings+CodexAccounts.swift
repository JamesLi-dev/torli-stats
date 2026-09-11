import SwiftUI
import AppKit

extension AppSettings {
    func addCodexManagedAccount(named displayName: String) -> CodexAccountConfiguration? {
        let rootURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".torli-stats-codex", isDirectory: true)
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? StatsL10n.format("codex.settings.account_number", codexManagedAccounts.count + 1) : trimmedName
        let baseDirectoryName = codexDirectoryName(for: resolvedName)
        let directoryName = uniqueCodexDirectoryName(base: baseDirectoryName, rootURL: rootURL)
        let homeURL = rootURL.appendingPathComponent(directoryName, isDirectory: true)

        do {
            try FileManager.default.createDirectory(
                at: homeURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: rootURL.path)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: homeURL.path)
        } catch {
            return nil
        }

        let account = CodexAccountConfiguration(
            id: UUID(),
            displayName: resolvedName,
            homePath: homeURL.path,
            isDashboardVisible: true,
            isStatusBarIncluded: true
        )
        codexManagedAccounts.append(account)
        return account
    }

    private func codexDirectoryName(for displayName: String) -> String {
        let latinName = displayName
            .applyingTransform(.toLatin, reverse: false)?
            .folding(options: .diacriticInsensitive, locale: .current) ?? displayName
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let slug = latinName.lowercased().unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(String(scalar)) : "-"
        }
        let result = String(slug)
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return result.isEmpty ? "account" : result
    }

    private func uniqueCodexDirectoryName(base: String, rootURL: URL) -> String {
        var candidate = base
        var index = 2
        while FileManager.default.fileExists(atPath: rootURL.appendingPathComponent(candidate).path) {
            candidate = "\(base)-\(index)"
            index += 1
        }
        return candidate
    }

    func startCodexLogin(for account: CodexAccountConfiguration) -> Bool {
        guard account.id != CodexAccountConfiguration.defaultAccountID,
              let executable = CodexUsageClient.executableURL() else {
            return false
        }

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("torli-stats-codex-login-\(account.id.uuidString).command")
        let script = "#!/bin/bash\nexport CODEX_HOME=\(shellQuoted(account.homePath))\n\(shellQuoted(executable.path)) login\nrm -f -- \"$0\"\n"
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-a", "Terminal", scriptURL.path]
            try task.run()
            return true
        } catch {
            try? FileManager.default.removeItem(at: scriptURL)
            return false
        }
    }

    func removeCodexManagedAccount(id: UUID) {
        codexManagedAccounts.removeAll { $0.id == id }
    }

    func updateCodexManagedAccount(_ account: CodexAccountConfiguration) {
        guard let index = codexManagedAccounts.firstIndex(where: { $0.id == account.id }) else { return }
        codexManagedAccounts[index] = account
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\\"'\\\"'"))'"
    }

    static func loadCodexManagedAccounts(from data: Data?) -> [CodexAccountConfiguration] {
        guard let data,
              let accounts = try? JSONDecoder().decode([CodexAccountConfiguration].self, from: data) else {
            return []
        }
        return accounts.filter { account in
            account.id != CodexAccountConfiguration.defaultAccountID &&
                account.homePath.hasPrefix((NSHomeDirectory() as NSString).appendingPathComponent(".torli-stats-codex") + "/")
        }
    }

}
