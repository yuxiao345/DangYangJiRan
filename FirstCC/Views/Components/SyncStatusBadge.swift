import SwiftUI
import CloudKit

struct SyncStatusBadge: View {
    @EnvironmentObject private var appContainer: AppContainer

    var body: some View {
        Button {
            Task { try? await appContainer.syncService?.syncNow() }
        } label: {
            HStack(spacing: 4) {
                switch appContainer.syncStatus {
                case .synced:
                    Image(systemName: "icloud.fill")
                        .font(.caption2)
                    Text("已同步")
                        .font(.caption2)
                case .syncing:
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 12, height: 12)
                    Text("同步中...")
                        .font(.caption2)
                case .offline:
                    Image(systemName: "icloud.slash")
                        .font(.caption2)
                    Text("离线")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                case .error(let msg):
                    Image(systemName: "exclamationmark.icloud")
                        .font(.caption2)
                    Text(msg)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
}
