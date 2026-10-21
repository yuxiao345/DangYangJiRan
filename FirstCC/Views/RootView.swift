import SwiftUI
@preconcurrency import CoreData

struct RootView: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @State private var isLocked = false
    @State private var isQuickAddPresented = false

    var body: some View {
        Group {
            if appContainer.currentLedger != nil {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .onAppear {
            appContainer.configureDefaultLedger()
            consumePendingQuickAction()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                processRecurring()
                appContainer.validateCurrentLedgerShare()
            case .background:
                if appLockEnabled { isLocked = true }
            default: break
            }
        }
        .onChange(of: appContainer.pendingQuickAction) { _, _ in
            consumePendingQuickAction()
        }
        .onChange(of: appContainer.currentLedger?.id) { _, _ in
            // 冷启动：快捷动作先于账本加载到达，等 currentLedger 就绪再弹。
            consumePendingQuickAction()
        }
        .onChange(of: isLocked) { _, locked in
            if !locked { consumePendingQuickAction() }
        }
        .sheet(isPresented: $isQuickAddPresented) {
            AddEditTransactionView()
        }
        .fullScreenCover(isPresented: $isLocked) {
            AppLockView()
        }
        .alert("共享失败", isPresented: Binding(get: { appContainer.shareErrorMessage != nil }, set: { if !$0 { appContainer.shareErrorMessage = nil } })) {
            // System default OK button auto-dismisses the alert.
        } message: {
            Text(appContainer.shareErrorMessage ?? "")
        }
    }

    /// 消费长按图标的快捷动作，条件不满足就挂着等下一次状态变化。
    ///
    /// 账本必须已就绪，否则 `AddEditTransactionView.loadData()` 返回空表；
    /// 锁屏时不能弹，全屏 App 锁与 sheet 同时呈现会冲突。
    private func consumePendingQuickAction() {
        guard appContainer.pendingQuickAction == .addTransaction,
              appContainer.currentLedger != nil,
              !isLocked else { return }
        // 记一笔已经开着，这次点击视为已满足，必须清掉 —— 否则残留的 pending
        // 会在之后某个无关的状态变化里突然弹出来。
        appContainer.pendingQuickAction = nil
        if !isQuickAddPresented { isQuickAddPresented = true }
    }

    private func processRecurring() {
        guard appContainer.currentLedger != nil else { return }
        Task { @MainActor in
            // 生成要等本次启动第一次 CloudKit 导入落地，否则本设备会为"别端已经生成过、
            // 但还没同步过来"的期间再补一条 —— 那是跨设备重复的根因（去重只是事后清理）。
            // 离线/未登录 iCloud 时该等待超时返回 false，退回"照常生成 + 事后去重"。
            await appContainer.coreDataStack.waitForImportSinceLaunch()
            guard appContainer.currentLedger != nil else { return }
            do {
                try appContainer.recurringService.processDueRecurring(context: modelContext)
                // 跨设备去重每天最多执行一次（前台事件），远程变化观察者不受限
                let lastKey = "lastRecurringDedup"
                let last = UserDefaults.standard.object(forKey: lastKey) as? Date ?? .distantPast
                if Date().timeIntervalSince(last) >= 86400 {
                    try appContainer.recurringService.deduplicateRecurringTransactions(context: modelContext)
                    UserDefaults.standard.set(Date(), forKey: lastKey)
                }
            }
            catch { DiagnosticLog.log("processRecurring FAILED: \(error.localizedDescription)") }
        }
    }
}
