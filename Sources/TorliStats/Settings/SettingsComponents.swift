import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsFieldLabel: View {
    let title: String
    let width: CGFloat

    init(_ title: String, width: CGFloat = 78) {
        self.title = title
        self.width = width
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: .leading)
            .lineLimit(1)
    }
}

struct SettingsInlineHint: View {
    let text: String
    var icon = "info.circle"

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 2)
    }
}

struct SettingsSubsectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        HStack(spacing: 6) {
            Capsule()
                .fill(Color.secondary.opacity(0.45))
                .frame(width: 3, height: 11)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

struct StatusBarMetricGroupDropDelegate: DropDelegate {
    let target: StatusBarMetricGroup
    @Binding var groups: [StatusBarMetricGroup]
    @Binding var draggedGroup: StatusBarMetricGroup?

    func dropEntered(info: DropInfo) {
        guard let draggedGroup,
              draggedGroup != target,
              let sourceIndex = groups.firstIndex(of: draggedGroup),
              let destinationIndex = groups.firstIndex(of: target) else {
            return
        }

        withAnimation(.easeInOut(duration: 0.15)) {
            groups.move(
                fromOffsets: IndexSet(integer: sourceIndex),
                toOffset: destinationIndex > sourceIndex ? destinationIndex + 1 : destinationIndex
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedGroup = nil
        return true
    }
}

struct DashboardModuleDropDelegate: DropDelegate {
    let target: DashboardModule
    @Binding var modules: [DashboardModule]
    @Binding var draggedModule: DashboardModule?

    func dropEntered(info: DropInfo) {
        guard let draggedModule,
              draggedModule != target,
              let sourceIndex = modules.firstIndex(of: draggedModule),
              let destinationIndex = modules.firstIndex(of: target) else {
            return
        }
        withAnimation(.easeInOut(duration: 0.15)) {
            modules.move(
                fromOffsets: IndexSet(integer: sourceIndex),
                toOffset: destinationIndex > sourceIndex ? destinationIndex + 1 : destinationIndex
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedModule = nil
        return true
    }
}
/// A behind-window material surface covers the full-size content view,
/// including the transparent titlebar, for one continuous frosted treatment.
struct SettingsWindowBackground: View {
    var body: some View {
        ZStack {
            SettingsGlassBackdrop()
            AppColors.settingsGlassTint
                .allowsHitTesting(false)
        }
    }
}

private struct SettingsGlassBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
    }
}

/// A shared, macOS-style navigation row used by the main and Notes settings
/// windows. System colours keep the selection legible in both appearances.
struct SettingsSidebarItem: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .regular))
                    .frame(width: 20, height: 18)
                Text(title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
            }
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(isSelected ? AppColors.badge : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Sidebar selection is represented by its fill; keyboard focus should
        // not add AppKit's blue focus ring to an unselected navigation row.
        .focusable(false)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    let cardMinHeight: CGFloat
    let content: Content

    init(title: String, cardMinHeight: CGFloat = 0, @ViewBuilder content: () -> Content) {
        self.title = title
        self.cardMinHeight = cardMinHeight
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(StatsL10n.text(title))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 9) {
                content
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: cardMinHeight, alignment: .topLeading)
            .settingsCardSurface()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsStatusMessage: View {
    let text: String
    var icon: String? = nil
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 7) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
            }
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

struct SettingsDestructiveActionRow: View {
    let title: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.red)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button(actionTitle, role: .destructive, action: action)
                .buttonStyle(.bordered)
                .tint(.red)
        }
        .padding(.vertical, 3)
    }
}

struct SettingsReorderRow: View {
    let title: String
    var systemImage = "line.3.horizontal"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .font(.callout)
                .frame(width: 14)
            Text(title)
                .font(.callout)
                .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.and.down")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct SettingsTabItem: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .background(isSelected ? Color.primary.opacity(0.13) : .clear)
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(isSelected ? Color.primary.opacity(0.13) : .clear, lineWidth: 0.8)
                }
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .shadow(color: isSelected ? Color.black.opacity(0.055) : .clear, radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SettingsCardSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AppColors.card)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.018))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.36),
                                Color.primary.opacity(0.055),
                                Color.black.opacity(0.08)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.8
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: Color.black.opacity(0.045), radius: 9, y: 3)
    }
}

extension View {
    func settingsCardSurface() -> some View {
        modifier(SettingsCardSurface())
    }
}
