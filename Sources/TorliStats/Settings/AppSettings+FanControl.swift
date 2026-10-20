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

        fanControlApplying = true
        fanControlMessage = nil
        sensorClient.setFanControl(mode: mode) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.fanControlApplying = false
                guard result.success else {
                    self.fanControlMode = .automatic
                    self.fanControlMessage = StatsL10n.text("fan.control.apply_failed")
                    return
                }
                self.fanControlMode = result.mode ?? mode
                self.fanControlMessage = StatsL10n.text(
                    mode == .automatic ? "fan.control.automatic_applied" : "fan.control.mode_applied"
                )
            }
        }
    }
}
