import Foundation
import TorliStatsShared

extension AppSettings {
    func applyFanControl(mode: FanControlMode) {
        guard sensorHelperEnabled else {
            fanControlMode = .automatic
            fanControlMessage = StatsL10n.text("fan.control.helper_required")
            return
        }
        guard mode == .automatic || sensorFanAvailable else {
            fanControlMode = .automatic
            fanControlMessage = StatsL10n.text("fan.control.unavailable")
            return
        }
        guard !fanControlApplying else { return }

        let command = mode == .cooling ? FanControlMode.cooling : mode
        fanControlApplying = true
        fanControlMessage = nil
        sensorClient.setFanControl(mode: command) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.fanControlApplying = false
                guard result.success else {
                    self.fanControlMode = .automatic
                    self.appliedFanCoolingTarget = nil
                    self.finishFanControlTransition()
                    self.fanControlMessage = StatsL10n.text("fan.control.apply_failed")
                    return
                }
                self.fanControlMode = mode
                self.appliedFanCoolingTarget = mode == .cooling ? command : nil
                if mode == .automatic {
                    self.finishFanControlTransition()
                } else {
                    self.beginFanControlTransition(to: command)
                }
                self.fanControlMessage = StatsL10n.text(
                    mode == .automatic ? "fan.control.automatic_applied" : "fan.control.mode_applied"
                )
            }
        }
    }

    /// The cooling preset starts at 40% of maximum fan speed and raises its
    /// target only when fresh thermal or CPU-load data warrants it. The card
    /// remains in the user-facing `.cooling` mode while the helper receives
    /// its allow-listed internal target steps.
    func updateFanCoolingTarget(
        cpuTemperature: Double?,
        gpuTemperature: Double?,
        cpuUsage: Double
    ) {
        guard fanControlMode == .cooling,
              sensorHelperEnabled,
              sensorFanAvailable,
              !fanControlApplying else { return }

        let maximumTemperature = [cpuTemperature, gpuTemperature].compactMap { $0 }.max()
        let target = FanControlMode.coolingTarget(
            maximumTemperature: maximumTemperature,
            cpuUsage: cpuUsage
        )
        guard target != appliedFanCoolingTarget else { return }

        fanControlApplying = true
        sensorClient.setFanControl(mode: target) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.fanControlApplying = false
                guard result.success else {
                    self.fanControlMode = .automatic
                    self.appliedFanCoolingTarget = nil
                    self.finishFanControlTransition()
                    self.fanControlMessage = StatsL10n.text("fan.control.apply_failed")
                    return
                }
                // Do not let an older asynchronous adjustment overwrite a
                // mode the user selected while its helper request was pending.
                guard self.fanControlMode == .cooling else { return }
                self.appliedFanCoolingTarget = target
                self.beginFanControlTransition(to: target)
            }
        }
    }

    /// Keeps the UI in its transitional state until the physical fan has had
    /// time to approach its commanded RPM. Sensor polls normally settle this
    /// within five seconds; a timeout prevents a stale sensor from wedging it.
    func updateFanControlTransition(currentRPM: Int?, maximumRPM: Int?) {
        guard fanControlTransitioning,
              let target = fanControlTransitionTarget,
              let currentRPM,
              let maximumRPM,
              let targetRPM = target.targetRPM(minimum: 0, maximum: Double(maximumRPM)) else {
            return
        }

        if Double(currentRPM) >= targetRPM * 0.9 {
            finishFanControlTransition()
        }
    }

    private func beginFanControlTransition(to target: FanControlMode) {
        fanControlTransitionWorkItem?.cancel()
        fanControlTransitionTarget = target
        fanControlTransitioning = true

        let workItem = DispatchWorkItem { [weak self] in
            self?.finishFanControlTransition()
        }
        fanControlTransitionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: workItem)
    }

    private func finishFanControlTransition() {
        fanControlTransitionWorkItem?.cancel()
        fanControlTransitionWorkItem = nil
        fanControlTransitionTarget = nil
        fanControlTransitioning = false
    }
}
