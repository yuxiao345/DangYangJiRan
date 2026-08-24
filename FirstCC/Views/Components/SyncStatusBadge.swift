import SwiftUI
import CloudKit
import UIKit

struct SyncStatusBadge: View {
    @Environment(AppContainer.self) private var appContainer
#if DEBUG
    @State private var showDetail = false
#endif

    var body: some View {
#if DEBUG
        Button {
            showDetail = true
        } label: {
            statusIcon
                .foregroundStyle(statusColor)
        }
        .buttonStyle(.plain)
        .alert("共享调试版本 v2", isPresented: $showDetail) {
            Button("复制日志") {
                UIPasteboard.general.string = diagnosticText
            }
            if case .error = appContainer.syncStatus {
                Button("重试同步") {
                    Task { try? await appContainer.syncService?.syncNow() }
                }
            }
            Button("确定", role: .cancel) {}
        } message: {
            Text(diagnosticText)
        }
#else
        statusIcon
            .foregroundStyle(statusColor)
#endif
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch appContainer.syncStatus {
        case .synced:
            Image(systemName: "ladybug.fill")
                .font(.designBodySmall)
        case .syncing:
            Image(systemName: "ladybug")
                .font(.designBodySmall)
        case .offline:
            Image(systemName: "wifi.slash")
                .font(.designBodySmall)
        case .shareInvalid:
            Image(systemName: "person.slash")
                .font(.designBodySmall)
        case .error:
            Image(systemName: "ant.circle.fill")
                .font(.designBodySmall)
        }
    }

#if DEBUG
    private var diagnosticText: String {
        let status = appContainer.syncStatus.displayName
        let log = DiagnosticLog.read()

        // UserDefaults diagnostic counters
        let willConnectFired = UserDefaults.standard.integer(forKey: "diag_willConnectFired")
        let willConnectHasMetadata = UserDefaults.standard.bool(forKey: "diag_willConnectHasMetadata")
        let sceneFired = UserDefaults.standard.integer(forKey: "diag_sceneDelegateFired")
        let sceneSharedOK = UserDefaults.standard.bool(forKey: "diag_sceneDelegateSharedOK")
        let sceneSharedNil = UserDefaults.standard.bool(forKey: "diag_sceneDelegateSharedNil")
        let sceneRetry = UserDefaults.standard.integer(forKey: "diag_sceneDelegateRetrySuccess")
        let sceneFailed = UserDefaults.standard.bool(forKey: "diag_sceneDelegateFailed")
        let openURLContextsFired = UserDefaults.standard.integer(forKey: "diag_openURLContextsFired")
        let appDelOpenURL = UserDefaults.standard.integer(forKey: "diag_appDelegateOpenURL")
        let onOpenFired = UserDefaults.standard.integer(forKey: "diag_onOpenURLFired")
        let onOpenResolved = UserDefaults.standard.bool(forKey: "diag_onOpenURLResolved")
        let onOpenError = UserDefaults.standard.string(forKey: "diag_onOpenURLError") ?? ""

        let acceptOK = UserDefaults.standard.bool(forKey: "diag_acceptInvitationOK")
        let importCount = UserDefaults.standard.integer(forKey: "diag_importLedgerCount")
        let acceptError = UserDefaults.standard.string(forKey: "diag_shareAcceptError") ?? ""
        let acceptStartTime = UserDefaults.standard.double(forKey: "diag_acceptFlowStartTime")

        var udDiag = "--- UserDefaults 追踪 ---\n"
        udDiag += "willConnect 次数: \(willConnectFired)\n"
        udDiag += "willConnect 有metadata: \(willConnectHasMetadata ? "是" : "否")\n"
        udDiag += "SceneDelegate 次数: \(sceneFired)\n"
        udDiag += "openURLContexts 次数: \(openURLContextsFired)\n"
        udDiag += "AppDelegate openURL 次数: \(appDelOpenURL)\n"
        udDiag += "onOpenURL 次数: \(onOpenFired)\n"
        if sceneSharedOK { udDiag += "AppContainer直接可用: 是\n" }
        if sceneSharedNil { udDiag += "AppContainer为nil: 是\n" }
        if sceneRetry > 0 { udDiag += "重试成功(第\(sceneRetry)次): 是\n" }
        if sceneFailed { udDiag += "10次重试全失败: 是\n" }
        if onOpenResolved { udDiag += "onOpenURL解析成功: 是\n" }
        if !onOpenError.isEmpty { udDiag += "onOpenURL错误: \(onOpenError)\n" }
        udDiag += "--- 接受流程 ---\n"
        udDiag += "acceptInvitation结果: \(acceptOK ? "成功" : (acceptError.isEmpty ? "未触发" : "失败"))\n"
        if !acceptError.isEmpty { udDiag += "accept错误: \(acceptError)\n" }
        udDiag += "导入账本数: \(importCount)\n"
        if acceptStartTime > 0 {
            let elapsed = Int(Date.now.timeIntervalSince1970 - acceptStartTime)
            udDiag += "距接受开始: \(elapsed)秒\n"
        }

        return "[共享调试版本 v5]\n\n状态:\n\(status)\n\n\(udDiag)\n诊断日志:\n\(log)"
    }
#endif

    private var statusColor: Color {
        switch appContainer.syncStatus {
        case .offline: .orange
        case .error: .red
        case .shareInvalid: .orange
        default: .secondary
        }
    }
}
