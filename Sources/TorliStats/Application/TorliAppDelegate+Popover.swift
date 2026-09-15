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
        let targetHeight = min(estimatedHeight, DashboardView.maximumPopoverHeight)
        if abs(popover.contentSize.height - targetHeight) > 0.5 {
            popover.contentSize = NSSize(width: DashboardView.panelWidth, height: targetHeight)
        }

        // 内容较长时将 popover 限制在可用的阅读高度，Dashboard 内部负责滚动。
        // Do not force a full fitting pass while the popover is hidden; this is
        // also important when a background WakaTime update arrives.
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.popover.isShown,
                  let view = self.popover.contentViewController?.view else { return }
            view.layoutSubtreeIfNeeded()
            let fittedHeight = view.fittingSize.height
            guard fittedHeight > 0 else { return }
            let fittedTargetHeight = min(fittedHeight, DashboardView.maximumPopoverHeight)
            guard abs(self.popover.contentSize.height - fittedTargetHeight) > 0.5 else { return }
            self.popover.contentSize = NSSize(width: DashboardView.panelWidth, height: fittedTargetHeight)
        }
    }

    func schedulePopoverSizeUpdate() {
        popoverSizeUpdateWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.popoverSizeUpdateWorkItem = nil
            self?.updatePopoverSize()
        }
        popoverSizeUpdateWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
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
            updatePopoverSize()
            monitoringPauseController.setDashboardVisible(true)
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
        monitoringPauseController.setDashboardVisible(false)
    }

}
