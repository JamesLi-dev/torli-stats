import SwiftUI

struct SensorCapabilityRow: View {
    let title: String
    let isAvailable: Bool
    let reason: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: isAvailable ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(isAvailable ? .green : .secondary)
            Text(title)
                .font(.caption.weight(.medium))
                .frame(width: 58, alignment: .leading)
            Text(reason)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .help(reason)
    }
}
