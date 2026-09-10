import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension SettingsView {
    var sensorsSection: some View {
        SettingsSection(title: StatsL10n.text("sensor.settings.title")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: settings.sensorHelperEnabled ? "checkmark.shield.fill" : "exclamationmark.shield")
                        .foregroundStyle(settings.sensorHelperEnabled ? .green : (settings.sensorHelperReachable ? .orange : .secondary))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(settings.sensorHelperEnabled ? StatsL10n.text("sensor.settings.helper_running") : (settings.sensorHelperReachable ? StatsL10n.text("sensor.settings.helper_reinstall_required") : StatsL10n.text("sensor.settings.unauthorized_or_unavailable")))
                            .font(.callout.weight(.semibold))
                        Text(settings.sensorHelperMessage ?? StatsL10n.text("sensor.settings.authorization_required"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 5) {
                        HStack(spacing: 6) {
                            PowerTag(text: "Helper \(settings.sensorHelperVersion ?? "—")")
                            PowerTag(text: StatsL10n.format("sensor.settings.protocol", settings.sensorProtocolVersion.map(String.init) ?? "—"))
                        }
                        if settings.sensorHelperChecking {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }

                if let diagnostic = settings.sensorOperationDiagnostic {
                    Text(diagnostic)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(diagnostic)
                }

                Text(settings.sensorSignatureMessage ?? StatsL10n.text("sensor.settings.signature_not_verified"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 150), spacing: 10),
                        GridItem(.flexible(minimum: 150), spacing: 10)
                    ],
                    alignment: .leading,
                    spacing: 6
                ) {
                    SensorCapabilityRow(
                        title: StatsL10n.text("sensor.fan"),
                        isAvailable: settings.sensorFanAvailable,
                        reason: settings.sensorFanReason
                    )
                    SensorCapabilityRow(
                        title: StatsL10n.text("sensor.cpu_temperature_short"),
                        isAvailable: settings.sensorCPUTemperatureAvailable,
                        reason: settings.sensorCPUTemperatureReason
                    )
                    SensorCapabilityRow(
                        title: StatsL10n.text("sensor.gpu_temperature_short"),
                        isAvailable: settings.sensorGPUTemperatureAvailable,
                        reason: settings.sensorGPUTemperatureReason
                    )
                }

                if let lastReadAt = settings.sensorLastReadAt {
                    Text(StatsL10n.format("sensor.settings.last_read", lastReadAt.formatted(date: .omitted, time: .shortened)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Button(settings.sensorHelperReachable ? StatsL10n.text("sensor.settings.reinstall") : StatsL10n.text("sensor.settings.authorize")) {
                        settings.installSensorHelper()
                    }
                    .disabled(settings.sensorHelperChecking)

                    Button(StatsL10n.text("sensor.settings.recheck")) {
                        settings.refreshSensorStatus()
                    }
                    .disabled(settings.sensorHelperChecking)

                    Button(StatsL10n.text("sensor.settings.copy_diagnostics")) {
                        settings.copySensorDiagnostics()
                    }
                    .disabled(settings.sensorHelperChecking)

                    if settings.sensorHelperReachable {
                        Button(StatsL10n.text("sensor.settings.uninstall"), role: .destructive) {
                            settings.uninstallSensorHelper()
                        }
                        .disabled(settings.sensorHelperChecking)
                    }
                }
            }
        }
    }
}
