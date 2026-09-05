import SwiftUI
import UniformTypeIdentifiers

struct SettingsFieldLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 72, alignment: .leading)
            .lineLimit(1)
    }
}

struct SettingsSubsectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: cardMinHeight, alignment: .topLeading)
            .background(AppColors.card)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: Color.black.opacity(0.04), radius: 8, y: 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
