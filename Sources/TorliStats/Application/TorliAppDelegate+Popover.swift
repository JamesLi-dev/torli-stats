import AppKit
import SwiftUI

extension TorliAppDelegate {
    @objc func handleStatusItemClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    func updatePopoverSize(codexAccountCount: Int? = nil) {
        let visibleAccountCount = codexAccountCount
            ?? min(2, codexUsageStore.accounts.filter(\.isDashboardVisible).count)
        let estimatedHeight = DashboardView.preferredHeight(
            for: settings,
            codexAccountCount: visibleAccountCount
        )
        popover.contentSize = NSSize(
            width: 360,
            height: min(estimatedHeight, DashboardView.maximumPopoverHeight)
        )

        // 内容较长时将 popover 限制在可用的阅读高度，Dashboard 内部负责滚动。
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let view = self.popover.contentViewController?.view else { return }
            view.layoutSubtreeIfNeeded()
            let fittedHeight = view.fittingSize.height
            guard fittedHeight > 0 else { return }
            self.popover.contentSize = NSSize(
                width: 360,
                height: min(fittedHeight, DashboardView.maximumPopoverHeight)
            )
        }
    }
    private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            closePopover()
        } else {
            popover.show(
                relativeTo: button.bounds,
                of: button,
                preferredEdge: .minY
            )
            startOutsideClickMonitors()
        }
    }

    func closePopover() {
        stopOutsideClickMonitors()
        popover.performClose(nil)
    }

    private func startOutsideClickMonitors() {
        stopOutsideClickMonitors()

        localOutsideClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self, self.popover.isShown else { return event }
            let popoverWindow = self.popover.contentViewController?.view.window
            let statusWindow = self.statusItem?.button?.window
            if event.window !== popoverWindow && event.window !== statusWindow {
                self.closePopover()
            }
            return event
        }

        globalOutsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            guard let self, self.popover.isShown else { return }
            self.closePopover()
        }
    }

    func stopOutsideClickMonitors() {
        if let localOutsideClickMonitor {
            NSEvent.removeMonitor(localOutsideClickMonitor)
            self.localOutsideClickMonitor = nil
        }
        if let globalOutsideClickMonitor {
            NSEvent.removeMonitor(globalOutsideClickMonitor)
            self.globalOutsideClickMonitor = nil
        }
    }

    func popoverDidClose(_ notification: Notification) {
        stopOutsideClickMonitors()
    }

}
