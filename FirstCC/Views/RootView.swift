import SwiftUI
@preconcurrency import CoreData

struct RootView: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @State private var isLocked = false

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
        .fullScreenCover(isPresented: $isLocked) {
            AppLockView()
        }
        .alert("共享失败", isPresented: Binding(get: { appContainer.shareErrorMessage != nil }, set: { if !$0 { appContainer.shareErrorMessage = nil } })) {
            Button("好") { appContainer.shareErrorMessage = nil }
        } message: {
            Text(appContainer.shareErrorMessage ?? "")
        }
    }

    private func processRecurring() {
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
