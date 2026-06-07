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
    }

    private func processRecurring() {
        guard appContainer.currentLedger != nil else { return }
        try? appContainer.recurringService.processDueRecurring(context: modelContext)
    }
}
