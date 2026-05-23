import SwiftUI
import CloudKit
import UIKit

struct SyncStatusBadge: View {
    @EnvironmentObject private var appContainer: AppContainer
    @State private var showDetail = false

    var body: some View {
        Button {
            if case .error = appContainer.syncStatus {
                showDetail = true
            } else {
                Task { try? await appContainer.syncService?.syncNow() }
            }
        } label: {
            statusIcon
                .foregroundStyle(statusColor)
        }
        .buttonStyle(.plain)
        .alert("同步诊断", isPresented: $showDetail) {
            Button("复制日志") {
                UIPasteboard.general.string = appContainer.syncStatus.displayName
            }
            Button("确定", role: .cancel) {}
        } message: {
            Text(appContainer.syncStatus.displayName)
        }
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
