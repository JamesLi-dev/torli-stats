import AppKit
import SwiftUI
import ServiceManagement

extension SettingsView {
    func exportSettingsBackup() {
        guard let password = backupPassword(confirm: true) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Torli-Settings.torlibackup"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            settings.flushCodexTextPersistence()
            let token = try WakaTimeKeychain.readOAuthTokenForBackup()
            let name = Bundle.main.bundleIdentifier ?? "local.torli.stats"
            let domain = UserDefaults.standard.persistentDomain(forName: name) ?? [:]
            let encrypted = try SettingsBackup.encode(SettingsBackup.snapshot(domain: domain, wakaToken: token,
                                                                                 launchAtLogin: try backupLoginStatus()), password: password)
            try encrypted.write(to: url, options: .atomic)
        } catch SettingsBackup.BackupError.launchUnavailable {
            backupLoginError()
        } catch { backupError() }
    }

    func importSettingsBackup() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let password = backupPassword(confirm: false) else { return }
        do {
            let snapshot = try SettingsBackup.decode(SettingsBackup.readFile(at: url), password: password)
            let warning = NSAlert()
            warning.messageText = StatsL10n.text("settings.backup.confirm_title")
            warning.informativeText = StatsL10n.text("settings.backup.confirm_body")
            warning.addButton(withTitle: StatsL10n.text("settings.backup.restore_quit"))
            warning.addButton(withTitle: StatsL10n.text("settings.backup.cancel"))
            guard warning.runModal() == .alertFirstButtonReturn else { return }
            guard NoteStore.shared.flushAll() else {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = StatsL10n.text("settings.backup.notes_unsaved")
                alert.runModal()
                return
            }
            settings.flushCodexTextPersistence()
            try SettingsBackup.restore(snapshot, defaults: .standard,
                domainName: Bundle.main.bundleIdentifier ?? "local.torli.stats",
                readToken: { try WakaTimeKeychain.readOAuthTokenForBackup() },
                readLaunch: { try backupLoginStatus() },
                writeLaunch: { try setBackupLoginStatus($0) }) { token in
                try SharedCredentialVault.shared.write(token.map { Data($0.utf8) } ?? Data(), for: "wakatime.oauth")
            }
            let done = NSAlert()
            done.messageText = StatsL10n.text("settings.backup.restored")
            done.informativeText = StatsL10n.text("settings.backup.restart_required")
            done.runModal()
            NSApp.terminate(nil)
        } catch SettingsBackup.BackupError.rollbackFailed {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = StatsL10n.text("settings.backup.rollback_failed")
            alert.informativeText = StatsL10n.text("settings.backup.rollback_failed_help")
            alert.runModal()
        } catch SettingsBackup.BackupError.launchUnavailable {
            backupLoginError()
        } catch SettingsBackup.BackupError.launchRestoreFailed {
            backupLoginError()
        } catch { backupError() }
    }

    private func backupLoginStatus() throws -> Bool {
        switch SMAppService.mainApp.status {
        case .enabled: return true
        case .notRegistered: return false
        default: throw SettingsBackup.BackupError.launchUnavailable
        }
    }

    private func setBackupLoginStatus(_ enabled: Bool) throws {
        if (try? backupLoginStatus()) == enabled { return }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        guard try backupLoginStatus() == enabled else { throw SettingsBackup.BackupError.launchRestoreFailed }
    }

    private func backupLoginError() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = StatsL10n.text("settings.backup.login_failed")
        alert.informativeText = StatsL10n.text("settings.backup.login_failed_help")
        alert.runModal()
    }

    private func backupPassword(confirm: Bool) -> String? {
        let alert = NSAlert()
        alert.messageText = StatsL10n.text(confirm ? "settings.backup.new_password" : "settings.backup.password")
        alert.informativeText = StatsL10n.text("settings.backup.password_help")
        alert.addButton(withTitle: StatsL10n.text("settings.backup.continue"))
        alert.addButton(withTitle: StatsL10n.text("settings.backup.cancel"))
        let height: CGFloat = 24
        let width: CGFloat = 280
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: confirm ? 56 : height))
        let first = NSSecureTextField(frame: NSRect(x: 0, y: confirm ? 32 : 0, width: width, height: height))
        first.placeholderString = StatsL10n.text("settings.backup.password")
        container.addSubview(first)
        let second: NSSecureTextField?
        if confirm {
            let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: width, height: height))
            field.placeholderString = StatsL10n.text("settings.backup.confirm_password")
            container.addSubview(field)
            second = field
        } else {
            second = nil
        }
        alert.accessoryView = container
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        guard !first.stringValue.isEmpty, !confirm || first.stringValue == second?.stringValue else {
            let error = NSAlert()
            error.messageText = StatsL10n.text("settings.backup.password_invalid")
            error.runModal()
            return nil
        }
        return first.stringValue
    }

    private func backupError() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = StatsL10n.text("settings.backup.failed")
        alert.informativeText = StatsL10n.text("settings.backup.failed_help")
        alert.runModal()
    }
}
