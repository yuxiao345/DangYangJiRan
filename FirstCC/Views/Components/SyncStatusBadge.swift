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
                    .font(.designBodySmall)
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
                .font(.designBodySmall)
        case .syncing:
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 12, height: 12)
        case .offline:
            Image(systemName: "icloud.slash")
                .font(.designBodySmall)
        case .error:
            Image(systemName: "exclamationmark.icloud")
                .font(.designBodySmall)
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
