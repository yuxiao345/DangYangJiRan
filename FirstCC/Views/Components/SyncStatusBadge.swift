import SwiftUI
import CloudKit

struct SyncStatusBadge: View {
    @EnvironmentObject private var appContainer: AppContainer

    var body: some View {
        Button {
            Task { try? await appContainer.syncService?.syncNow() }
        } label: {
            HStack(spacing: 4) {
                statusIcon
                Text(appContainer.syncStatus.displayName)
                    .font(.caption2)
                    .foregroundStyle(statusColor)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch appContainer.syncStatus {
        case .synced:
            Image(systemName: "icloud.fill")
                .font(.caption2)
        case .syncing:
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 12, height: 12)
        case .offline:
            Image(systemName: "icloud.slash")
                .font(.caption2)
        case .error:
            Image(systemName: "exclamationmark.icloud")
                .font(.caption2)
        }
    }

    private var statusColor: Color {
        switch appContainer.syncStatus {
        case .offline: .orange
        case .error: .red
        default: .secondary
        }
    }
}
