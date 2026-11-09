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
        let screenHeight = statusItem.button?.window?.screen?.visibleFrame.height
            ?? NSScreen.main?.visibleFrame.height ?? DashboardView.maximumPopoverHeight
        let maximumHeight = min(DashboardView.maximumPopoverHeight, max(160, screenHeight - 16))
        guard !dashboardPanel.isShown else { return }
        let targetHeight = min(estimatedHeight, maximumHeight)
        if abs(dashboardPanel.dashboardContentSize.height - targetHeight) > 0.5 {
            dashboardPanel.dashboardContentSize = NSSize(width: DashboardView.panelWidth, height: targetHeight)
        }
    }

    func applyMeasuredPopoverHeight(_ height: CGFloat) {
        guard dashboardPanel.isShown, height.isFinite, height > 0 else { return }
        measuredHeightUpdateWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.dashboardPanel.isShown else { return }
            self.measuredHeightUpdateWorkItem = nil
            let screenHeight = self.statusItem.button?.window?.screen?.visibleFrame.height
                ?? NSScreen.main?.visibleFrame.height ?? DashboardView.maximumPopoverHeight
            let maximumHeight = min(DashboardView.maximumPopoverHeight, max(160, screenHeight - 16))
            let targetHeight = min(max(height, 160), maximumHeight)
            guard abs(self.dashboardPanel.dashboardContentSize.height - targetHeight) > 0.5 else { return }
            self.dashboardPanel.dashboardContentSize = NSSize(width: DashboardView.panelWidth, height: targetHeight)
        }
        measuredHeightUpdateWorkItem = workItem
        // Coalesce measurements within this layout pass without displaying the
        // new tab inside the old tab's frame for an extra 120ms.
        DispatchQueue.main.async(execute: workItem)
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

        if dashboardPanel.isShown {
            closePopover()
        } else {
            dashboardPanel.present(
                relativeTo: button.bounds,
                of: button,
                preferredEdge: .minY
            )
            updatePopoverSize()
            monitoringPauseController.setDashboardVisible(true)
            updateMetricsCollectionRequirements()
            startOutsideClickMonitors()
        }
    }

    func closePopover() {
        measuredHeightUpdateWorkItem?.cancel()
        measuredHeightUpdateWorkItem = nil
        stopOutsideClickMonitors()
        dashboardPanel.dismiss()
        FeatureRegistry.shared.dashboardDidClose()
        monitoringPauseController.setDashboardVisible(false)
        updateMetricsCollectionRequirements()
    }

    private func startOutsideClickMonitors() {
        stopOutsideClickMonitors()

        localOutsideClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self, self.dashboardPanel.isShown else { return event }
            // Status-item events are not consistently reported with the same
            // window identity as the status button. Use the screen-space
            // button rect as the fallback, otherwise this mouseDown closes
            // the panel before the button's mouseUp toggles it back open.
            if self.isStatusItemEvent(event) || event.window === self.dashboardPanel {
                return event
            }
            self.closePopover()
            return event
        }

        globalOutsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self, self.dashboardPanel.isShown else { return }
            // A status-item click can also arrive through the global monitor
            // while this accessory app is inactive. Let the button action
            // handle it so a mouseDown does not close and a mouseUp reopen
            // the panel.
            if self.isStatusItemEvent(event) { return }
            self.closePopover()
        }
    }

    private func isStatusItemEvent(_ event: NSEvent) -> Bool {
        guard let button = statusItem?.button,
              let window = button.window else { return false }
        if event.window === window { return true }

        let buttonRect = window.convertToScreen(button.convert(button.bounds, to: nil))
        return buttonRect.contains(NSEvent.mouseLocation)
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

}
