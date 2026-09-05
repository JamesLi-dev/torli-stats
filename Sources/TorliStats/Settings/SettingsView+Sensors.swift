import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension SettingsView {
    var sensorsSection: some View {
        SettingsSection(title: "传感器") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: settings.sensorHelperEnabled ? "checkmark.shield.fill" : "exclamationmark.shield")
                        .foregroundStyle(settings.sensorHelperEnabled ? .green : (settings.sensorHelperReachable ? .orange : .secondary))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(settings.sensorHelperEnabled ? "辅助进程运行中" : (settings.sensorHelperReachable ? "辅助进程需要重新安装" : "未授权或不可用"))
                            .font(.callout.weight(.semibold))
                        Text(settings.sensorHelperMessage ?? "需要管理员授权后读取风扇和温度。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 5) {
                        HStack(spacing: 6) {
                            PowerTag(text: "Helper \(settings.sensorHelperVersion ?? "—")")
                            PowerTag(text: "协议 \(settings.sensorProtocolVersion.map(String.init) ?? "—")")
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

                Text(settings.sensorSignatureMessage ?? "尚未验证辅助进程签名。")
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
                        title: "风扇",
                        isAvailable: settings.sensorFanAvailable,
                        reason: settings.sensorFanReason
                    )
                    SensorCapabilityRow(
                        title: "CPU 温度",
                        isAvailable: settings.sensorCPUTemperatureAvailable,
                        reason: settings.sensorCPUTemperatureReason
                    )
                    SensorCapabilityRow(
                        title: "GPU 温度",
                        isAvailable: settings.sensorGPUTemperatureAvailable,
                        reason: settings.sensorGPUTemperatureReason
                    )
                }

                if let lastReadAt = settings.sensorLastReadAt {
                    Text("上次成功读取：\(lastReadAt, style: .time)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Button(settings.sensorHelperReachable ? "重新安装" : "授权读取") {
                        settings.installSensorHelper()
                    }
                    .disabled(settings.sensorHelperChecking)

                    Button("重新检测") {
                        settings.refreshSensorStatus()
                    }
                    .disabled(settings.sensorHelperChecking)

                    Button("复制诊断") {
                        settings.copySensorDiagnostics()
                    }
                    .disabled(settings.sensorHelperChecking)

                    if settings.sensorHelperReachable {
                        Button("卸载", role: .destructive) {
                            settings.uninstallSensorHelper()
                        }
                        .disabled(settings.sensorHelperChecking)
                    }
                }
            }
        }
    }
}
