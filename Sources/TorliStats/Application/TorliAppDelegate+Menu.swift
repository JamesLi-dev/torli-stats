import AppKit
import SwiftUI

extension TorliAppDelegate {
    func showContextMenu() {
        guard let button = statusItem.button else { return }
        closePopover()

        let menu = NSMenu()
        menu.autoenablesItems = false
        // Privacy mode previously used NSMenuItem.state, which makes AppKit
        // reserve an empty state/checkmark column for every menu item. Use
        // matching symbols instead so the leading edges stay compact.
        menu.showsStateColumn = false

        let aboutItem = NSMenuItem(
            title: "关于 Torli Stats",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.image = menuSymbol("info.circle")
        menu.addItem(aboutItem)

        let settingsItem = NSMenuItem(
            title: "打开设置",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.image = menuSymbol("gearshape")
        menu.addItem(settingsItem)

        let notesToggleItem = NSMenuItem(
            title: NotesSettings.notesDeckEnabled ? "关闭桌面便签" : "开启桌面便签",
            action: #selector(toggleNotesDeck),
            keyEquivalent: ""
        )
        notesToggleItem.image = menuSymbol(NotesSettings.notesDeckEnabled ? "note.text" : "note.text.badge.plus")
        menu.addItem(notesToggleItem)

        if NotesSettings.notesDeckEnabled {
            let newNoteItem = NSMenuItem(title: "新建便签", action: #selector(newNote), keyEquivalent: "n")
            newNoteItem.image = menuSymbol("square.and.pencil")
            menu.addItem(newNoteItem)

            let allNotesItem = NSMenuItem(title: "全部便签", action: #selector(openAllNotes), keyEquivalent: "")
            allNotesItem.image = menuSymbol("note.text")
            menu.addItem(allNotesItem)
        }

        let noteSettingsItem = NSMenuItem(title: "便签设置…", action: #selector(openNoteSettings), keyEquivalent: "")
        noteSettingsItem.image = menuSymbol("slider.horizontal.3")
        menu.addItem(noteSettingsItem)
        menu.addItem(.separator())

        let refreshItem = NSMenuItem(
            title: "刷新全部数据",
            action: #selector(refreshAllData),
            keyEquivalent: "r"
        )
        refreshItem.image = menuSymbol("arrow.clockwise")
        menu.addItem(refreshItem)

        let privacyItem = NSMenuItem(
            title: "隐私展示模式",
            action: #selector(togglePrivacyMode),
            keyEquivalent: ""
        )
        privacyItem.image = menuSymbol(settings.privacyMode ? "eye.slash.fill" : "eye.slash")
        menu.addItem(privacyItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: "退出 Torli Stats",
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quitItem.image = menuSymbol("power")
        menu.addItem(quitItem)
        menu.items.forEach { $0.target = self }

        menu.popUp(
            positioning: nil,
            at: NSPoint(x: button.bounds.midX, y: button.bounds.minY - 4),
            in: button
        )
    }

    private func menuSymbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    @objc private func refreshAllData() {
        store.refreshNow()
        codexUsageStore.refresh()
    }

    @objc private func togglePrivacyMode() {
        settings.privacyMode.toggle()
    }

    @objc private func showAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版本"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        let system = ProcessInfo.processInfo.operatingSystemVersion
        let sensorStatus = settings.sensorHelperEnabled ? "已授权" : "未授权或不可用"
        let alert = NSAlert()
        alert.messageText = "Torli Stats"
        alert.informativeText = "版本 \(version)（构建 \(build)）\n架构：\(appArchitecture)\n系统：macOS \(system.majorVersion).\(system.minorVersion).\(system.patchVersion)\n传感器辅助进程：\(sensorStatus)"
        alert.addButton(withTitle: "好")
        alert.addButton(withTitle: "复制诊断信息")
        alert.addButton(withTitle: "第三方许可证")

        switch alert.runModal() {
        case .alertSecondButtonReturn:
            copyDiagnosticInfo(version: version, build: build, sensorStatus: sensorStatus)
        case .alertThirdButtonReturn:
            if let noticeURL = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md") {
                NSWorkspace.shared.open(noticeURL)
            }
        default:
            break
        }
    }

    private var appArchitecture: String {
        #if arch(arm64)
        return "Apple Silicon"
        #elseif arch(x86_64)
        return "Intel"
        #else
        return "未知"
        #endif
    }

    private func copyDiagnosticInfo(version: String, build: String, sensorStatus: String) {
        let system = ProcessInfo.processInfo.operatingSystemVersion
        let diagnostic = """
        Torli Stats \(version) (\(build))
        架构：\(appArchitecture)
        系统：macOS \(system.majorVersion).\(system.minorVersion).\(system.patchVersion)
        传感器辅助进程：\(sensorStatus)
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostic, forType: .string)
    }
    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }
}
